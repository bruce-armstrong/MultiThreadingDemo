using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace PbBackground;

/// <summary>
/// Runs work on .NET thread-pool threads and notifies a PowerBuilder window via PostMessage.
///
/// THE GOLDEN RULE: code running on a background thread must never call into PowerBuilder.
/// It only posts a Windows message. PowerBuilder handles that message on its own UI thread
/// (a user event mapped to pbm_customNN) and then calls back into this class to fetch results.
///
/// Message contract (wParam is always the job id):
///   WM_JOB_DONE     (WM_USER + 0 = pbm_custom01)  lParam = 0
///   WM_JOB_PROGRESS (WM_USER + 1 = pbm_custom02)  lParam = percent complete (0-100)
///   WM_JOB_FAILED   (WM_USER + 2 = pbm_custom03)  lParam = 2 (error) or 3 (cancelled)
///
/// Only types PowerBuilder can marshal are used in the public surface:
///   C# int  = PB long,   C# long = PB longlong,   C# string = PB string,   C# bool = PB boolean
/// </summary>
public class BackgroundWorker
{
    public const int WM_USER = 0x0400;
    public const int WM_JOB_DONE = WM_USER + 0;
    public const int WM_JOB_PROGRESS = WM_USER + 1;
    public const int WM_JOB_FAILED = WM_USER + 2;

    public const int STATUS_RUNNING = 0;
    public const int STATUS_DONE = 1;
    public const int STATUS_FAILED = 2;
    public const int STATUS_CANCELLED = 3;
    public const int STATUS_UNKNOWN = -1;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    private sealed class Job
    {
        public readonly CancellationTokenSource Cts = new();
        public volatile int Status = STATUS_RUNNING;
        public string Result = "";
        public string Error = "";
    }

    private readonly ConcurrentDictionary<int, Job> _jobs = new();
    private int _lastJobId;

    // ---------------------------------------------------------------------------------------
    // Public API called from PowerBuilder (always on the PB UI thread)
    // ---------------------------------------------------------------------------------------

    /// <summary>
    /// Starts a background job that counts primes up to <paramref name="limit"/>.
    /// Returns immediately with the job id. <paramref name="hwnd"/> is PB's Handle(window);
    /// pass 0 to skip notifications and poll with GetStatus instead.
    /// </summary>
    public int StartPrimeJob(int limit, long hwnd)
    {
        return StartJob(hwnd, (job, jobId, report) => CountPrimes(limit, job.Cts.Token, report));
    }

    /// <summary>Requests cancellation. Returns false if the job id is unknown.</summary>
    public bool CancelJob(int jobId)
    {
        if (!_jobs.TryGetValue(jobId, out var job)) return false;
        job.Cts.Cancel();
        return true;
    }

    /// <summary>Cancels every running job and forgets all jobs. Call from the window's close event.</summary>
    public void CancelAll()
    {
        foreach (var job in _jobs.Values) job.Cts.Cancel();
        _jobs.Clear();
    }

    public int GetStatus(int jobId) =>
        _jobs.TryGetValue(jobId, out var job) ? job.Status : STATUS_UNKNOWN;

    /// <summary>Returns the JSON result and releases the job. Empty string if not finished/unknown.</summary>
    public string GetResult(int jobId)
    {
        if (_jobs.TryGetValue(jobId, out var job) && job.Status == STATUS_DONE)
        {
            _jobs.TryRemove(jobId, out _);
            return job.Result;
        }
        return "";
    }

    /// <summary>Returns the error text and releases the job.</summary>
    public string GetError(int jobId)
    {
        if (_jobs.TryGetValue(jobId, out var job) &&
            (job.Status == STATUS_FAILED || job.Status == STATUS_CANCELLED))
        {
            _jobs.TryRemove(jobId, out _);
            return job.Error;
        }
        return "";
    }

    public int ActiveJobCount() => _jobs.Values.Count(j => j.Status == STATUS_RUNNING);

    // ---------------------------------------------------------------------------------------
    // Plumbing
    // ---------------------------------------------------------------------------------------

    /// <summary>
    /// Generic job runner. <paramref name="work"/> runs on a thread-pool thread, receives a
    /// progress callback (percent), and returns the result string (JSON by convention).
    /// To add your own job types, add another public StartXxxJob method that calls this.
    /// </summary>
    private int StartJob(long hwnd, Func<Job, int, Action<int>, string> work)
    {
        int jobId = Interlocked.Increment(ref _lastJobId);
        var job = new Job();
        _jobs[jobId] = job;
        var hWnd = new IntPtr(hwnd);

        int lastPercent = -1;
        void Report(int percent)
        {
            // Throttle: only post when the percentage actually changes (max ~100 messages/job),
            // so we never flood the PB message queue.
            if (percent == lastPercent) return;
            lastPercent = percent;
            Post(hWnd, WM_JOB_PROGRESS, jobId, percent);
        }

        Task.Run(() =>
        {
            try
            {
                job.Result = work(job, jobId, Report);
                job.Status = STATUS_DONE;
                Post(hWnd, WM_JOB_DONE, jobId, 0);
            }
            catch (OperationCanceledException)
            {
                job.Error = "Cancelled";
                job.Status = STATUS_CANCELLED;
                Post(hWnd, WM_JOB_FAILED, jobId, STATUS_CANCELLED);
            }
            catch (Exception ex)
            {
                // Never let an exception escape a background thread: it would kill the PB process.
                job.Error = ex.Message;
                job.Status = STATUS_FAILED;
                Post(hWnd, WM_JOB_FAILED, jobId, STATUS_FAILED);
            }
        });

        return jobId;
    }

    private static void Post(IntPtr hWnd, int msg, int jobId, int lParam)
    {
        // PostMessage (not SendMessage): returns immediately, so a worker can never deadlock
        // waiting on a busy UI thread. If the window is gone it simply returns false.
        if (hWnd != IntPtr.Zero)
            PostMessage(hWnd, msg, new IntPtr(jobId), new IntPtr(lParam));
    }

    // ---------------------------------------------------------------------------------------
    // Sample workload: deliberately CPU-heavy so the UI-responsiveness benefit is obvious.
    // Replace with your own work (file processing, HTTP calls, DB work on its OWN connection...).
    // ---------------------------------------------------------------------------------------

    private static string CountPrimes(int limit, CancellationToken token, Action<int> report)
    {
        if (limit < 2) throw new ArgumentOutOfRangeException(nameof(limit), "Limit must be at least 2.");

        var sw = Stopwatch.StartNew();
        int count = 0;
        int largest = 0;
        int step = Math.Max(1, limit / 100);

        for (int n = 2; n <= limit; n++)
        {
            if (n % step == 0)
            {
                token.ThrowIfCancellationRequested();
                report((int)((long)n * 100 / limit));
            }
            if (IsPrime(n)) { count++; largest = n; }
        }
        report(100);

        return JsonSerializer.Serialize(new
        {
            limit,
            primeCount = count,
            largestPrime = largest,
            elapsedMs = sw.ElapsedMilliseconds,
            threadId = Environment.CurrentManagedThreadId
        });
    }

    private static bool IsPrime(int n)
    {
        if (n < 4) return n >= 2;
        if (n % 2 == 0) return false;
        for (int d = 3; (long)d * d <= n; d += 2)
            if (n % d == 0) return false;
        return true;
    }
}
