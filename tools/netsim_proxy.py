# Lossy-link simulator for tools/net_jitter_probe.gd (no tc netem needed).
# UDP proxy: listen 7800 -> 127.0.0.1:7799, delay 150ms +-40ms jitter, 5% loss each direction.
import socket,select,random,time,heapq
L=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);L.bind(("127.0.0.1",7800));L.setblocking(False)
up={};back={};q=[];n=0
def sched(sock,data,addr):
    global n
    if random.random()<0.05: return
    n+=1;heapq.heappush(q,(time.time()+max(0,random.gauss(0.150,0.040)),n,sock,data,addr))
while True:
    socks=[L]+list(up.values())
    t=0.002
    r,_,_=select.select(socks,[],[],t)
    for s in r:
        data,addr=s.recvfrom(65535)
        if s is L:
            if addr not in up:
                u=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);u.bind(("127.0.0.1",0));u.setblocking(False);up[addr]=u;back[u]=addr
            sched(up[addr],data,("127.0.0.1",7799))
        else: sched(L,data,back[s])
    now=time.time()
    while q and q[0][0]<=now:
        _,_,s,d,a=heapq.heappop(q); s.sendto(d,a)
