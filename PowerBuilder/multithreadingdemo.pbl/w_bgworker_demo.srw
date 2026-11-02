//objectcomments Demo: background work in .NET, results delivered to PB via PostMessage -> pbm_customNN events
forward
global type w_bgworker_demo from window
end type
type st_limit from statictext within w_bgworker_demo
end type
type sle_limit from singlelineedit within w_bgworker_demo
end type
type cb_start from commandbutton within w_bgworker_demo
end type
type cb_start4 from commandbutton within w_bgworker_demo
end type
type cb_cancel from commandbutton within w_bgworker_demo
end type
type cb_clickme from commandbutton within w_bgworker_demo
end type
type hpb_progress from hprogressbar within w_bgworker_demo
end type
type st_status from statictext within w_bgworker_demo
end type
type mle_log from multilineedit within w_bgworker_demo
end type
end forward

global type w_bgworker_demo from window
integer width = 2620
integer height = 1660
boolean titlebar = true
string title = "Background Worker Demo (.NET + PostMessage)"
boolean controlmenu = true
boolean minbox = true
boolean resizable = true
long backcolor = 67108864
string icon = "AppIcon!"
boolean center = true
event ue_job_done pbm_custom01
event ue_job_progress pbm_custom02
event ue_job_failed pbm_custom03
st_limit st_limit
sle_limit sle_limit
cb_start cb_start
cb_start4 cb_start4
cb_cancel cb_cancel
cb_clickme cb_clickme
hpb_progress hpb_progress
st_status st_status
mle_log mle_log
end type
global w_bgworker_demo w_bgworker_demo

type variables
n_cst_bgworker	inv_worker
long	il_jobs[]			// ids of jobs started from this window
long	il_progress_job	// job whose progress the bar shows (most recently started)
long	il_clicks
end variables

forward prototypes
public subroutine wf_log (string as_msg)
public function long wf_start_job ()
public subroutine wf_refresh_status ()
end prototypes

public subroutine wf_log (string as_msg);mle_log.text += String(Now(), "hh:mm:ss.fff") + "   " + as_msg + "~r~n"
mle_log.Scroll(mle_log.LineCount())
end subroutine

public function long wf_start_job ();long ll_limit, ll_jobid
longlong lll_hwnd

ll_limit = Long(sle_limit.text)
if ll_limit < 2 then ll_limit = 2

// Handle() of THIS window: the .NET worker will PostMessage to it.
lll_hwnd = Handle(this)

ll_jobid = inv_worker.of_start_prime_job(ll_limit, lll_hwnd)
if ll_jobid < 0 then
	wf_log("ERROR starting job: " + inv_worker.is_lasterror)
	return -1
end if

il_jobs[UpperBound(il_jobs) + 1] = ll_jobid
il_progress_job = ll_jobid
hpb_progress.Position = 0
wf_log("Job " + String(ll_jobid) + " started (primes up to " + String(ll_limit, "#,##0") + ") - call returned immediately")
wf_refresh_status()
return ll_jobid
end function

public subroutine wf_refresh_status ();st_status.text = "Active jobs: " + String(inv_worker.of_active_job_count())
end subroutine

event ue_job_done;// .NET posts WM_USER+0/1/2, which PB exposes as pbm_custom01/02/03 (ue_job_done/progress/failed).
// wparam = job id; lparam = percent (progress) or status (failed/cancelled).
// These events run on the PB UI thread, so it is safe to touch any PB object here.
long ll_jobid, ll_root
string ls_json, ls_err
JsonParser lnv_json

ll_jobid = Long(wparam)
ls_json = inv_worker.of_get_result(ll_jobid)
if ls_json = "" then return 0	// already collected (e.g. a late duplicate message)

lnv_json = create JsonParser
ls_err = lnv_json.LoadString(ls_json)
if Len(ls_err) > 0 then
	wf_log("Job " + String(ll_jobid) + " returned unreadable JSON: " + ls_err)
else
	ll_root = lnv_json.GetRootItem()
	wf_log("Job " + String(ll_jobid) + " DONE: " + &
		String(lnv_json.GetItemNumber(ll_root, "primeCount"), "#,##0") + " primes, largest " + &
		String(lnv_json.GetItemNumber(ll_root, "largestPrime"), "#,##0") + ", " + &
		String(lnv_json.GetItemNumber(ll_root, "elapsedMs"), "#,##0") + " ms on .NET thread " + &
		String(lnv_json.GetItemNumber(ll_root, "threadId")))
end if
destroy lnv_json

if ll_jobid = il_progress_job then hpb_progress.Position = 100
wf_refresh_status()
return 0
end event

event ue_job_progress;long ll_jobid

ll_jobid = Long(wparam)
if ll_jobid = il_progress_job then
	hpb_progress.Position = lparam
	st_status.text = "Job " + String(ll_jobid) + ": " + String(lparam) + "%   |   Active jobs: " + &
		String(inv_worker.of_active_job_count())
end if
return 0
end event

event ue_job_failed;long ll_jobid
string ls_error

ll_jobid = Long(wparam)
ls_error = inv_worker.of_get_error(ll_jobid)

if lparam = inv_worker.STATUS_CANCELLED then
	wf_log("Job " + String(ll_jobid) + " cancelled")
else
	wf_log("Job " + String(ll_jobid) + " FAILED: " + ls_error)
end if

wf_refresh_status()
return 0
end event

on w_bgworker_demo.create
this.st_limit=create st_limit
this.sle_limit=create sle_limit
this.cb_start=create cb_start
this.cb_start4=create cb_start4
this.cb_cancel=create cb_cancel
this.cb_clickme=create cb_clickme
this.hpb_progress=create hpb_progress
this.st_status=create st_status
this.mle_log=create mle_log
this.Control[]={this.st_limit,&
this.sle_limit,&
this.cb_start,&
this.cb_start4,&
this.cb_cancel,&
this.cb_clickme,&
this.hpb_progress,&
this.st_status,&
this.mle_log}
end on

on w_bgworker_demo.destroy
destroy(this.st_limit)
destroy(this.sle_limit)
destroy(this.cb_start)
destroy(this.cb_start4)
destroy(this.cb_cancel)
destroy(this.cb_clickme)
destroy(this.hpb_progress)
destroy(this.st_status)
destroy(this.mle_log)
end on

event open;inv_worker = create n_cst_bgworker

if inv_worker.of_init() <> 1 then
	MessageBox("Background Worker", inv_worker.is_lasterror, StopSign!)
	cb_start.enabled = false
	cb_start4.enabled = false
	cb_cancel.enabled = false
	return
end if

wf_log("Worker ready. Start a few jobs, then click 'Click me' / move the window - the UI stays responsive.")
wf_refresh_status()
end event

event close;// Cancel first so no worker posts to this window after it is destroyed.
if IsValid(inv_worker) then
	inv_worker.of_cancel_all()
	destroy inv_worker
end if
end event

event resize;mle_log.width = newwidth - mle_log.x - 40
mle_log.height = newheight - mle_log.y - 40
hpb_progress.width = newwidth - hpb_progress.x - 40
end event

type st_limit from statictext within w_bgworker_demo
integer x = 37
integer y = 52
integer width = 517
integer height = 64
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
long textcolor = 33554432
long backcolor = 67108864
string text = "Count primes up to:"
boolean focusrectangle = false
end type

type sle_limit from singlelineedit within w_bgworker_demo
integer x = 571
integer y = 40
integer width = 402
integer height = 88
integer taborder = 10
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
long textcolor = 33554432
string text = "30000000"
borderstyle borderstyle = stylelowered!
end type

type cb_start from commandbutton within w_bgworker_demo
integer x = 1006
integer y = 36
integer width = 357
integer height = 96
integer taborder = 20
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
string text = "&Start job"
end type

event clicked;wf_start_job()
end event

type cb_start4 from commandbutton within w_bgworker_demo
integer x = 1381
integer y = 36
integer width = 384
integer height = 96
integer taborder = 30
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
string text = "Start &4 jobs"
end type

event clicked;// Four jobs run truly in parallel on the .NET thread pool.
integer li_i

for li_i = 1 to 4
	if wf_start_job() < 0 then exit
next
end event

type cb_cancel from commandbutton within w_bgworker_demo
integer x = 1783
integer y = 36
integer width = 357
integer height = 96
integer taborder = 40
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
string text = "&Cancel all"
end type

event clicked;// Cancel each job individually so each one reports back through ue_job_failed.
// (of_cancel_all() is for shutdown: it also forgets the jobs, so no events follow.)
long ll_i

for ll_i = 1 to UpperBound(il_jobs)
	if inv_worker.of_get_status(il_jobs[ll_i]) = inv_worker.STATUS_RUNNING then
		inv_worker.of_cancel(il_jobs[ll_i])
	end if
next
end event

type cb_clickme from commandbutton within w_bgworker_demo
integer x = 2158
integer y = 36
integer width = 384
integer height = 96
integer taborder = 50
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
string text = "Click me"
end type

event clicked;// Proof that the UI thread is free while jobs run.
il_clicks++
this.text = "Clicked " + String(il_clicks)
end event

type hpb_progress from hprogressbar within w_bgworker_demo
integer x = 37
integer y = 172
integer width = 2505
integer height = 64
unsignedinteger maxposition = 100
integer setstep = 1
end type

type st_status from statictext within w_bgworker_demo
integer x = 37
integer y = 256
integer width = 2505
integer height = 64
integer textsize = -10
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = variable!
fontfamily fontfamily = swiss!
string facename = "Tahoma"
long textcolor = 33554432
long backcolor = 67108864
string text = "Active jobs: 0"
boolean focusrectangle = false
end type

type mle_log from multilineedit within w_bgworker_demo
integer x = 37
integer y = 340
integer width = 2505
integer height = 1180
integer taborder = 60
integer textsize = -9
integer weight = 400
fontcharset fontcharset = ansi!
fontpitch fontpitch = fixed!
fontfamily fontfamily = modern!
string facename = "Consolas"
long textcolor = 33554432
boolean vscrollbar = true
boolean autovscroll = true
boolean displayonly = true
borderstyle borderstyle = stylelowered!
end type
