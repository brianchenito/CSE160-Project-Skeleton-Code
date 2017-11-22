//#include "../../packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/tcppayload.h"


generic module TransportP()
{
	provides interface Transport;
	uses interface Hashmap<socket_store_t> as sockets;
}
implementation
{
	socket_t nextSock;
	socket_addr_t nextAddr;

	void start();
	socket_t socket();
	error_t bind(socket_t fd, socket_addr_t addr);
	socket_t accept(socket_t fd);
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
		nextAddr.addr=ROOT_SOCKET_ADDR;
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
		dbg(GENERAL_CHANNEL,"binding %d\n",fd);
		if(tempstore.state==ESTABLISHED||tempstore.state==SYN_SENT||tempstore.state==SYN_RCVD)
		{
			dbg(GENERAL_CHANNEL,"Failure to bind, socket is currently occupied\n");
			return FAIL;
		}
		tempstore.src=addr.port;

		call sockets.insert(fd, tempstore);
		dbg(GENERAL_CHANNEL,"Set port to %d\n",(call sockets.get(fd)).src);
		return SUCCESS;
	}
	command socket_t Transport.accept(socket_t fd)
	{
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
		tcppayload payload;
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
		dbg(GENERAL_CHANNEL,"Socket %d ready to listen.\n",fd);
		return SUCCESS;
	}
}