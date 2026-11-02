# PowerBuilder background work: .NET + PostMessage

Real multi-threading for PowerBuilder without shared objects. The work runs on .NET thread-pool
threads, and PowerBuilder is notified through ordinary Windows messages that it handles on its own
UI thread.

```
 PB UI thread                                   .NET thread pool
 ─────────────                                  ────────────────
 cb_start.clicked
   inv_worker.of_start_prime_job(n, Handle(w)) ─► Task.Run( work )          (returns at once)
 ... UI stays fully responsive ...                 │
 ue_job_progress (pbm_custom02)  ◄── PostMessage ──┤ WM_USER+1, wParam=job, lParam=%
 ue_job_done     (pbm_custom01)  ◄── PostMessage ──┘ WM_USER+0, wParam=job
   inv_worker.of_get_result(job) ─────────────────► returns JSON, releases job
```

**The one rule:** background threads never call into PowerBuilder. They only `PostMessage`.
PowerBuilder then calls .NET (synchronously, on the UI thread) to collect the result.

## Files

| File | What it is |
|---|---|
| `MultiThreadingDemo.pbsln` | PowerBuilder 2025 R2 solution: open this in the IDE |
| `MultiThreadingDemo.pbproj` | PowerBuilder project (application `multithreadingdemo`) |
| `build.ps1` | Builds the .NET worker and the PB app, and assembles a runnable folder |
| `PbBackground/BackgroundWorker.cs` | C# class: job tracking, cancellation, throttled progress, PostMessage |
| `PbBackground/PbBackground.csproj` | .NET 8 class library |
| `PowerBuilder/multithreadingdemo.pbl/` | Solution-format library (a folder of source files) |
| `.../multithreadingdemo.sra` | Application object; its `open` event opens the demo window |
| `.../n_cst_bgworker.sru` | NVO inheriting `DotNetObject`; loads the assembly and wraps each method in try/catch |
| `.../w_bgworker_demo.srw` | Demo window: start 1 or 4 jobs, progress bar, cancel, log, "Click me" responsiveness test |
| `.../p_multithreadingdemo_exe.srj` | EXE build settings |

## Requirements

- PowerBuilder **2025 R2**. The solution targets runtime 25.1.0.6430. The code itself works from
  PB 2022 R2 (`DotNetAssembly.LoadWithDotNetCore` with .NET 6/8), but older versions need the
  objects imported into their own target. For PB 2019 R3+ with .NET Framework, retarget the
  project to `net48` and use `LoadWithDotNet`.
- The **.NET 8 runtime matching your app's bitness**: x86 for a 32-bit app, x64 for a 64-bit build.
- The .NET 8 SDK, to build the worker.

## Build and run

```bash
pwsh -File build.ps1
```

This produces `build/multithreadingdemo/`, containing the EXE, PBD and worker DLL. Run
`multithreadingdemo.exe` from there. Add `-Platform 64` for a 64-bit build, which goes to
`build/multithreadingdemo-x64/`.

To run from the IDE, run `build.ps1` once (it also copies the worker DLL to the solution folder),
then open `MultiThreadingDemo.pbsln`. If the demo reports it can't load the DLL, set
`n_cst_bgworker.is_assemblypath` to an absolute path.

Try **Start 4 jobs**, then click **Click me** or drag the window around. The jobs run in parallel
on different .NET threads (the log shows each one's thread id), and the UI never freezes.

## Using this in your own application

Copy `n_cst_bgworker.sru` into one of your libraries, add the user events to your window (see
`w_bgworker_demo.srw`), and deploy `PbBackground.dll` and `PbBackground.deps.json` with your EXE.
The two source files have no export header, so in a PBL-based (workspace) target, add a
`$PBExportHeader$` line first or import them through the solution.

## The message contract

| .NET posts | PB event | wparam | lparam |
|---|---|---|---|
| `WM_USER + 0` | `ue_job_done` (`pbm_custom01`) | job id | 0 |
| `WM_USER + 1` | `ue_job_progress` (`pbm_custom02`) | job id | percent 0–100 |
| `WM_USER + 2` | `ue_job_failed` (`pbm_custom03`) | job id | 2 = error, 3 = cancelled |

If your window already uses `pbm_custom01-03`, change the constants in `BackgroundWorker.cs`
(`pbm_customNN` = `WM_USER + NN - 1`) and the event mappings together.

## Adding your own job types

Add a public method to `BackgroundWorker` that calls the private `StartJob` helper:

```csharp
public int StartExportJob(string folder, long hwnd) =>
    StartJob(hwnd, (job, id, report) =>
    {
        // ... do work, call report(percent), check job.Cts.Token ...
        return JsonSerializer.Serialize(new { files = 42 });
    });
```

Then add a matching `of_start_export_job` wrapper in `n_cst_bgworker`. For tabular results,
return a JSON array of row objects and load it straight into a DataWindow with
`dw_1.ImportJson(ls_json)`.

## Gotchas

- **Database work:** a background job must open its **own** connection, for example with
  `Microsoft.Data.SqlClient` or Oracle's ODP.NET. Never pass it SQLCA or any PB transaction object.
- **Types across the boundary:** stick to `int` (PB `long`), `long` (PB `longlong`), `string`,
  `bool`, and arrays of those. Return complex data as JSON.
- **Window lifetime:** the window's `close` event calls `of_cancel_all()` before the window is
  destroyed. A message posted to a dead handle is simply dropped.
- **Use PostMessage, never SendMessage:** `SendMessage` blocks the worker until PB handles the
  message. That can deadlock if PB is busy and waiting on the worker.
- **Don't flood the queue:** progress is posted only when the percentage changes, at most about
  100 messages per job.
- **Exceptions:** every job body is wrapped in try/catch. An unhandled exception on a
  background thread would terminate the whole PB process.
- **Method names:** call .NET methods with their exact casing, and avoid names that collide with
  PowerScript built-ins (for example `Start` or `Run`).
- **Debugging:** you can attach Visual Studio to `pb*.exe` or your app's EXE (managed debugging)
  to step through the C# side while PB is running.

## License

MIT. See [LICENSE](LICENSE).
