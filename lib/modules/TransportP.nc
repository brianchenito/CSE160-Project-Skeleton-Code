//#include "../../packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/tcppayload.h"


generic module TransportP()
{
    provides interface Transport;
    uses interface Hashmap<socket_store_t> as sockets;
    uses interface Hashmap<socket_t> as boundports; 
    uses interface Hashmap<socket_addr_t> as activeconnectionrequests;
}
implementation
{
    socket_t nextSock;
    socket_addr_t nextAddr;

    void start();
    socket_t getSock(socket_port_t port);
    socket_port_t getPort(socket_t sock);
    enum socket_state  getState(socket_t fd);
    error_t establish(socket_t fd, socket_addr_t dest);
    socket_t socket();
    error_t bind(socket_t fd, socket_addr_t addr);
    socket_t accept(socket_t fd,socket_addr_t clientaddr);
    uint16_t write(socket_t fd, uint8_t *buff, uint16_t bufflen);
    error_t receive(pack* package);
    uint16_t read(socket_t fd, uint8_t *buff, uint16_t bufflen);
    tcppayload connect(socket_t fd, socket_addr_t addr);
    error_t close(socket_t fd);
    error_t release(socket_t fd);
    error_t listen(socket_t fd);

    command void Transport.start()
    {
        dbg(GENERAL_CHANNEL,"Configuring Transport \n");
        nextSock=1;
        nextAddr.port=ROOT_SOCKET_PORT;
        nextAddr.addr=TOS_NODE_ID;
    }
    command socket_t Transport.getSock(socket_port_t port)
    {
        if(call boundports.contains(port)){
            //dbg(GENERAL_CHANNEL,"socket %d retrieved from port %d\n",call boundports.get(port),port);
            return call boundports.get(port);
        }
        return NULL;
    }
    command socket_port_t Transport.getPort(socket_t sock)
    {
        if(call sockets.contains(sock))
        {
            return (call sockets.get(sock)).src;
        }
        return NULL;
    }

    command enum socket_state Transport.getState(socket_t fd)
    {
        if(call sockets.contains(fd))
        {
            return (call sockets.get(fd)).state;
        }
        return INVALID;
    }

    command error_t Transport.establish(socket_t fd, socket_addr_t dest)
    {
        socket_store_t tempstore;
        tempstore=call sockets.get(fd);
        if(tempstore.state==ESTABLISHED)
        {
            dbg(GENERAL_CHANNEL,"error, socket is already attached to port %d, addr %d\n",tempstore.dest.port, tempstore.dest.addr);
            return FAIL;
        }
        if(tempstore.state==SYN_RCVD||tempstore.state==SYN_SENT)
        {
            tempstore.state=ESTABLISHED;
            tempstore.dest=dest;
            call sockets.insert(fd,tempstore);
             dbg(GENERAL_CHANNEL,"---- SUCESSFUL ESTABLISHMENT WITH NODE %d ON PORT %d----\n",dest.addr,dest.port);
            return SUCCESS;
        }
        dbg(GENERAL_CHANNEL,"---- FAILURE TO ESTABLISH WITH NODE %d ON PORT %d(PORT %d CURR IN STATE %d )\n",dest.addr,dest.port,tempstore.src,tempstore.state);
        return FAIL;

    }

    command socket_t Transport.socket()
    {
        int i;
        uint32_t*keys;
        socket_t retval;
        socket_store_t tempstore;
        if(call sockets.size()>=MAX_NUM_OF_SOCKETS )
        {
            // check for a free socket
            for(i=0;i<MAX_NUM_OF_SOCKETS;i++)
            {
                keys=call sockets.getKeys();
                if((call sockets.get(keys[i])).state== CLOSED)
                {
                    dbg(GENERAL_CHANNEL,"Found closed socket, reusing \n");
                    return (socket_t)(keys[i]);
                }
            }
            dbg(GENERAL_CHANNEL,"All Sockets occupied, failure to get \n");
            return NULL;
        }
        
        retval=nextSock;
        dbg(GENERAL_CHANNEL,"Generating a new socket with id %d \n",retval);
        nextSock+=1;
        call sockets.insert(retval, tempstore);

        return retval;
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t addr)
    {   
        socket_store_t tempstore;
        tempstore=(call sockets.get(fd));
        //dbg(GENERAL_CHANNEL,"binding %d\n",fd);
        if(tempstore.state==ESTABLISHED||tempstore.state==SYN_SENT||tempstore.state==SYN_RCVD)
        {
            dbg(GENERAL_CHANNEL,"Failure to bind, socket is currently occupied\n");
            return FAIL;
        }
        tempstore.src=addr.port;

        call sockets.insert(fd, tempstore);
        call boundports.insert(addr.port, fd);

        dbg(GENERAL_CHANNEL,"Socket %d on addr %d set port to %d\n",fd,nextAddr.addr,(call sockets.get(fd)).src);
        return SUCCESS;
    }
    command socket_t Transport.accept(socket_t fd,socket_addr_t clientaddr)
    {
        socket_store_t listsock;
        socket_t newsock;
        if(call sockets.contains(fd))
        {
            if(call activeconnectionrequests.contains(clientaddr.addr))
            {
                //dbg(GENERAL_CHANNEL,"Client already has a pending or active connection with Server\n");
                return NULL;
            }
            listsock=call sockets.get(fd);
            //dbg(GENERAL_CHANNEL,"socket %d contains target port,%d\n",fd,(call sockets.get(fd)).src);
            if(listsock.state==LISTEN)
                {

                    dbg(GENERAL_CHANNEL,"LISTENER CONFIRMED, GENERATING NEW SOCKET FOR CONNECTION\n");
                    newsock=call Transport.socket();
                    if(newsock==NULL){
                        dbg(GENERAL_CHANNEL,"FAILURE TO GENERATE NEW SOCKET\n");
                        return newsock;
                    }
                    call Transport.bind(newsock,nextAddr);
                    listsock=call sockets.get(newsock);
                    listsock.state=SYN_RCVD;
                    call activeconnectionrequests.insert(clientaddr.addr,clientaddr);
                    call sockets.insert(newsock,listsock);
                    dbg(GENERAL_CHANNEL,"sock %d set to state SYN_RCVD\n",newsock);
                    nextAddr.port+=1;
                    return newsock;
                }
        }
        dbg(GENERAL_CHANNEL,"failure to accept new connection\n");
        return NULL;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
    {
        return 0;
    }
    command error_t Transport.receive(pack* package)
    {  
        return FAIL;
    }
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
    {
        return 0;
    }
    command tcppayload Transport.connect(socket_t fd, socket_addr_t addr)
    {
        socket_store_t tempstore;
        tcppayload payload;
        dbg(GENERAL_CHANNEL,"socket %d  at port %d switching to SYN_SENT\n",fd, call Transport.getPort(fd));
        tempstore=(call sockets.get(fd));
        tempstore.state=SYN_SENT;
        call sockets.insert(fd, tempstore);
        
        dbg(GENERAL_CHANNEL,"Constructing a SYN packet from socket %d to port %d at node %d \n",fd, addr.port, addr.addr);
        payload.flag=FLAG_SYN;
        payload.sourceport=(call sockets.get(fd)).src;
        payload.destport=addr.port;
        return payload;
    }
    command error_t Transport.close(socket_t fd)
    {
        return FAIL;
    }
    command error_t Transport.release(socket_t fd)
    {
        return FAIL;
    }
    command error_t Transport.listen(socket_t fd)
    {
        socket_store_t tempstore;
        tempstore=(call sockets.get(fd));
        dbg(GENERAL_CHANNEL,"Converting socket on id %d to listener \n", fd);
        if(tempstore.state==ESTABLISHED||tempstore.state==SYN_SENT||tempstore.state==SYN_RCVD)
        {
            dbg(GENERAL_CHANNEL,"Failure to open listener, socket is currently occupied\n");
            return FAIL;
        }
        tempstore.state=LISTEN;
        call sockets.insert(fd, tempstore);
        dbg(GENERAL_CHANNEL,"Socket %d ready to listen, state %d.\n",fd,(call sockets.get(fd)).state);
        return SUCCESS;
    }
}