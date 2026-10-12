// AppDock, MIT. Credentials pass through stdin and PTY, never argv or logs.
#include <util.h>
#include <termios.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static pid_t child = -1;
static void wipe(char *value, size_t size) { volatile char *p = value; while (size--) *p++ = 0; }
static void stop(int sig) { if (child > 0) { kill(-child,SIGTERM); kill(child,SIGTERM); } _exit(128+sig); }
static int line(char *buf, size_t n) {
 size_t i=0; char c;
 while (read(STDIN_FILENO,&c,1)==1) { if(c=='\n') {buf[i]=0;return 1;} if(i+1>=n || c=='\r' || c==0)return 0;buf[i++]=c; }
 return 0;
}
static void event(const char *status) { printf("{\"status\":\"%s\"}\n",status); fflush(stdout); }
static int send_value(int fd, char *value) {
 size_t n=strlen(value),done=0;
 while(done<n) {ssize_t k=write(fd,value+done,n-done);if(k<=0)return 0;done+=(size_t)k;}
 return write(fd,"\n",1)==1;
}
int main(int argc,char **argv) {
 if(argc!=2)return 2;
 char email[4096]={0},password[4096]={0},code[128]={0};
 if(!line(email,sizeof(email)) || !line(password,sizeof(password)))return 2;
 signal(SIGTERM,stop);signal(SIGINT,stop);signal(SIGALRM,stop);alarm(600);
 int master,slave; struct termios settings;
 if(openpty(&master,&slave,NULL,NULL,NULL)!=0)return 3;
 tcgetattr(slave,&settings);settings.c_lflag &= ~(ECHO|ECHONL);tcsetattr(slave,TCSANOW,&settings);
 child=fork();
 if(child==0) { close(master);setsid();ioctl(slave,TIOCSCTTY,0);dup2(slave,0);dup2(slave,1);dup2(slave,2);if(slave>2)close(slave);execl(argv[1],argv[1],"--format","json","auth","login",NULL);_exit(127); }
 close(slave);if(child<0)return 3;
 int sent_email=0,sent_password=0,waiting_code=0,success=0,failed=0;char buffer[16384]={0};size_t used=0;
 event("running");
 while(1) {
  struct pollfd fds[2]={{master,POLLIN,0},{STDIN_FILENO,POLLIN,0}};
  if(poll(fds,2,500)<0)break;
  if(fds[1].revents&POLLHUP)break;
  if(waiting_code && (fds[1].revents&POLLIN)) {
   if(!line(code,sizeof(code)))break;
   if(!send_value(master,code))break;
   wipe(code,sizeof(code));waiting_code=0;used=0;buffer[0]=0;event("running");
  }
  if(fds[0].revents&POLLIN) {
   if(used>sizeof(buffer)-2048) {memmove(buffer,buffer+used-4096,4096);used=4096;}
   ssize_t n=read(master,buffer+used,sizeof(buffer)-used-1);if(n<=0)break;used+=(size_t)n;buffer[used]=0;
   if(strstr(buffer,"\"success\":true") || strstr(buffer,"\"success\": true"))success=1;
   if(!sent_email && strstr(buffer,"enter Apple ID")) {if(!send_value(master,email))break;sent_email=1;wipe(email,sizeof(email));used=0;buffer[0]=0;}
   else if(!sent_password && strstr(buffer,"enter password:")) {if(!send_value(master,password))break;sent_password=1;wipe(password,sizeof(password));used=0;buffer[0]=0;}
   else if(!waiting_code && strstr(buffer,"enter 2FA code:")) {waiting_code=1;used=0;buffer[0]=0;event("awaiting2fa");}
   else if(strstr(buffer,"passphrase to unlock")) {event("keychain_locked");failed=1;break;}
  }
  int status;pid_t done=waitpid(child,&status,WNOHANG);
  if(done==child) {child=-1;if(!WIFEXITED(status) || WEXITSTATUS(status)!=0)failed=1;break;}
  if(fds[0].revents&POLLHUP) { // Drain final JSON before the child exits.
   ssize_t n=read(master,buffer+used,sizeof(buffer)-used-1);
   if(n>0) {used+=(size_t)n;buffer[used]=0;if(strstr(buffer,"\"success\":true") || strstr(buffer,"\"success\": true"))success=1;}
   break;
  }
 }
 wipe(email,sizeof(email));wipe(password,sizeof(password));wipe(code,sizeof(code));
 if(child>0) {kill(-child,SIGTERM);kill(child,SIGTERM);waitpid(child,NULL,0);}close(master);
 if(success && !failed) {event("done");return 0;}event("failed");return 1;
}
