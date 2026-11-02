//objectcomments Demo application: opens w_bgworker_demo.
forward
global transaction sqlca
global dynamicdescriptionarea sqlda
global dynamicstagingarea sqlsa
global error error
global message message
end forward

global type multithreadingdemo from application
 string appruntimeversion = "25.1.0.6430"
integer highdpimode = 0
end type
global multithreadingdemo multithreadingdemo

on multithreadingdemo.create
appname = "multithreadingdemo"
message = create message
sqlca = create transaction
sqlda = create dynamicdescriptionarea
sqlsa = create dynamicstagingarea
error = create error
end on

on multithreadingdemo.destroy
destroy( sqlca )
destroy( sqlda )
destroy( sqlsa )
destroy( error )
destroy( message )
end on

event open;Open(w_bgworker_demo)
end event
