-- LuaJIT/POSIX integration test: real subprocesses and pipes, with the
-- KOReader ffi/util API supplied by a small native shim. No device UI needed.
local ffi = require("ffi")
ffi.cdef[[
int fork(void); int pipe(int fds[2]); int close(int fd);
long read(int fd, void *buf, unsigned long n);
long write(int fd, const void *buf, unsigned long n);
int waitpid(int pid, int *status, int options); int kill(int pid, int sig);
int setpgid(int pid, int pgid); int getpid(void); void _exit(int status);
int ioctl(int fd, unsigned long request, ...); int usleep(unsigned int us);
int fcntl(int fd, int cmd, ...);
struct timeval { long tv_sec; long tv_usec; };
int gettimeofday(struct timeval *tv, void *tz);
]]
local C=ffi.C
local function clock()
 local tv=ffi.new('struct timeval[1]');C.gettimeofday(tv,nil)
 return tonumber(tv[0].tv_sec)+tonumber(tv[0].tv_usec)/1000000
end
local offset=0
local util={}
function util.getTimestamp()return clock()+offset end
function util.runInSubProcess(task,with_pipe)
 assert(with_pipe==true)
 local fds=ffi.new('int[2]');assert(C.pipe(fds)==0)
 local pid=C.fork();assert(pid>=0,'fork failed')
 if pid==0 then
  C.close(fds[0]);C.setpgid(0,0)
  pcall(task,C.getpid(),tonumber(fds[1]));C._exit(0)
 end
 C.close(fds[1]);return tonumber(pid),tonumber(fds[0])
end
function util.isSubProcessDone(pid)
 local status=ffi.new('int[1]');return C.waitpid(pid,status,1)~=0
end
function util.terminateSubProcess(pid)
 -- The production util kills the process group. Kill the child directly in
 -- this test shim, avoiding a race with the child's setpgid after fork.
 C.kill(pid,9)
end
function util.getNonBlockingReadSize(fd)
 local available=ffi.new('int[1]')
 local request=ffi.os=='OSX'and 0x4004667f or 0x541b
 assert(C.ioctl(fd,request,available)==0)
 return tonumber(available[0])
end
package.preload['ffi/util']=function()return util end
local ui={tasks={},locks=0,ticks=0}
function ui:preventStandby()self.locks=self.locks+1 end
function ui:allowStandby()self.locks=self.locks-1;assert(self.locks>=0)end
function ui:scheduleIn(delay,fn)self.tasks[fn]=clock()+delay end
function ui:unschedule(fn)self.tasks[fn]=nil end
package.preload['ui/uimanager']=function()return ui end
local function pump(until_done)
 local deadline=clock()+5
 repeat
  ui.ticks=ui.ticks+1 -- simulate input processing between worker callbacks
  local due={}
  for fn,at in pairs(ui.tasks)do if clock()>=at then due[#due+1]=fn end end
  for _,fn in ipairs(due)do if ui.tasks[fn]then ui.tasks[fn]=nil;fn()end end
  assert(clock()<deadline,'worker or reaper did not finish')
  C.usleep(1000)
 until until_done()
end
local background=dofile('kobocodex.koplugin/background.lua')
local result
local start=clock()
local job=background.run(function()C.usleep(200000);return{answer='Complete answer'}end,function(ok,data)result={ok,data}end)
assert(clock()-start<0.1 and not result and ui.locks==1,'starting a slow request must return promptly')
pump(function()return result~=nil end)
assert(result[1]and result[2].answer=='Complete answer'and ui.ticks>20 and ui.locks==0)
assert(C.fcntl(job.fd or -1,1)==-1 and util.isSubProcessDone(job.pid))

-- Larger than the kernel pipe: must drain incrementally without deadlock.
result=nil;start=ui.ticks
job=background.run(function()return string.rep('x',2000000)end,function(ok,data)result={ok,data}end)
pump(function()return result~=nil end)
assert(result[1]and #result[2]==2000000 and ui.ticks-start>20 and ui.locks==0)
result=nil
background.run(function()error('Synthetic transport failure')end,function(ok,data)result={ok,data}end)
pump(function()return result~=nil end)
assert(not result[1]and result[2]:find('Synthetic transport failure',1,true))
result=nil
background.run(function()return string.rep('x',3100001)end,function(ok,data)result={ok,data}end)
pump(function()return result~=nil end)
assert(not result[1]and result[2]:find('too large',1,true))

-- Hard watchdog handles stuck DNS/transport too, closes its fd, balances
-- standby, and reaps without waiting synchronously for the child.
result=nil
job=background.run(function()C.usleep(3000000);return 'late'end,function(ok,data)result={ok,data}end)
local fd=job.fd;offset=21
pump(function()return result~=nil end);offset=0
assert(not result[1]and result[2]:find('timed out',1,true)and ui.locks==0 and C.fcntl(fd,1)==-1)
pump(function()return next(ui.tasks)==nil end)
assert(util.isSubProcessDone(job.pid))

result=nil
job=background.run(function()C.usleep(3000000);return 'late'end,function()result=true end)
fd=job.fd;job:cancel();job:cancel()
assert(ui.locks==0 and not result and C.fcntl(fd,1)==-1)
pump(function()return next(ui.tasks)==nil end)
assert(not result and util.isSubProcessDone(job.pid))
result=nil
background.run(function()C._exit(1)end,function(ok,data)result={ok,data}end)
pump(function()return result~=nil end)
assert(not result[1]and result[2]:find('valid result',1,true)and ui.locks==0)
print('Background worker checks passed: prompt return, UI ticks during delay and 2MB pipe transfer, errors, size bound, watchdog, cancellation, fd closure, child reaping, standby balance')
