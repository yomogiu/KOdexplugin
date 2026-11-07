#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <libproc.h>
static int blocked(const char* addr, int port) {
 int fd=socket(AF_INET,SOCK_STREAM,0); struct sockaddr_in sa={0};
 sa.sin_family=AF_INET;sa.sin_port=htons(port);inet_pton(AF_INET,addr,&sa.sin_addr);
 int r=connect(fd,(void*)&sa,sizeof(sa));int e=errno;close(fd);
 return r<0&&(e==EPERM||e==EACCES);
}
int main(int argc,char**argv) {
 if(argc!=5)return 2;
 int a=open(argv[1],O_RDONLY),b=open(argv[2],O_RDONLY);int be=errno;
 int allow=a>=0,deny=b<0&&(be==EPERM||be==EACCES);if(a>=0)close(a);if(b>=0)close(b);
 int proxy=!blocked("127.0.0.1",atoi(argv[3]));
 int local=blocked("127.0.0.1",atoi(argv[4]));
 int lan=blocked("192.168.0.1",443),public=blocked("8.8.8.8",443);
 char buf[PROC_PIDPATHINFO_MAXSIZE];int other=proc_pidpath(getppid(),buf,sizeof(buf))<=0;
 printf("{\"allowedFile\":%s,\"outsideFileBlocked\":%s,\"proxyReachable\":%s,\"otherLoopbackBlocked\":%s,\"lanBlocked\":%s,\"directInternetBlocked\":%s,\"otherProcessInspectionBlocked\":%s}\n",allow?"true":"false",deny?"true":"false",proxy?"true":"false",local?"true":"false",lan?"true":"false",public?"true":"false",other?"true":"false");
 return !(allow&&deny&&proxy&&local&&lan&&public&&other);
}
