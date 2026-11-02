//objectcomments Wrapper for PbBackground.BackgroundWorker (.NET). All calls are made from the PB UI thread.
forward
global type n_cst_bgworker from dotnetobject
end type
end forward

global type n_cst_bgworker from dotnetobject
end type
global n_cst_bgworker n_cst_bgworker

type variables
PUBLIC:
	// Relative paths resolve against the current directory (EXE folder at runtime,
	// workspace folder in the IDE). Use an absolute path while developing if needed.
	string	is_assemblypath = "PbBackground.dll"
	string	is_classname = "PbBackground.BackgroundWorker"
	string	is_lasterror

	// Message contract with the .NET side (wparam = job id)
	CONSTANT long	STATUS_RUNNING = 0
	CONSTANT long	STATUS_DONE = 1
	CONSTANT long	STATUS_FAILED = 2
	CONSTANT long	STATUS_CANCELLED = 3
	CONSTANT long	STATUS_UNKNOWN = -1

PRIVATE:
	DotNetAssembly	idn_assembly
	boolean	ib_ready = false
end variables

forward prototypes
public function integer of_init ()
public function long of_start_prime_job (long al_limit, longlong all_hwnd)
public function boolean of_cancel (long al_jobid)
public subroutine of_cancel_all ()
public function long of_get_status (long al_jobid)
public function string of_get_result (long al_jobid)
public function string of_get_error (long al_jobid)
public function long of_active_job_count ()
end prototypes

public function integer of_init ();// Loads the assembly and binds this object to a .NET BackgroundWorker instance.
// Returns 1 on success, -1 on failure (see is_lasterror).
integer li_rc

if ib_ready then return 1

idn_assembly = create DotNetAssembly
li_rc = idn_assembly.LoadWithDotNetCore(is_assemblypath)
if li_rc <> 1 then
	is_lasterror = "Could not load " + is_assemblypath + ": " + idn_assembly.ErrorText
	return -1
end if

li_rc = idn_assembly.CreateInstance(is_classname, this)
if li_rc <> 1 then
	is_lasterror = "Could not create " + is_classname + ": " + idn_assembly.ErrorText
	return -1
end if

ib_ready = true
return 1
end function

public function long of_start_prime_job (long al_limit, longlong all_hwnd);// Starts a job and returns its id immediately (-1 on error).
long ll_jobid

if not ib_ready then
	is_lasterror = "Worker not initialised"
	return -1
end if

try
	ll_jobid = this.StartPrimeJob(al_limit, all_hwnd)
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return -1
end try

return ll_jobid
end function

public function boolean of_cancel (long al_jobid);boolean lb_rc

if not ib_ready then return false

try
	lb_rc = this.CancelJob(al_jobid)
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return false
end try

return lb_rc
end function

public subroutine of_cancel_all ();if not ib_ready then return

try
	this.CancelAll()
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
end try
end subroutine

public function long of_get_status (long al_jobid);long ll_status

if not ib_ready then return STATUS_UNKNOWN

try
	ll_status = this.GetStatus(al_jobid)
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return STATUS_UNKNOWN
end try

return ll_status
end function

public function string of_get_result (long al_jobid);// Returns the job's JSON result and releases it on the .NET side.
string ls_result

if not ib_ready then return ""

try
	ls_result = this.GetResult(al_jobid)
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return ""
end try

return ls_result
end function

public function string of_get_error (long al_jobid);string ls_error

if not ib_ready then return ""

try
	ls_error = this.GetError(al_jobid)
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return ""
end try

return ls_error
end function

public function long of_active_job_count ();long ll_count

if not ib_ready then return 0

try
	ll_count = this.ActiveJobCount()
catch (RuntimeError lre_error)
	is_lasterror = lre_error.GetMessage()
	return 0
end try

return ll_count
end function

on n_cst_bgworker.create
call super::create
TriggerEvent( this, "constructor" )
end on

on n_cst_bgworker.destroy
TriggerEvent( this, "destructor" )
call super::destroy
end on

event destructor;// Make sure no background job tries to post to a window that is going away.
of_cancel_all()
if IsValid(idn_assembly) then destroy idn_assembly
end event
