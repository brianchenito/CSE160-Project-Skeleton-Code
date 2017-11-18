//#include "../../packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"
#include "../../includes/tcppayload.h"


generic module TransportP()
{
	provides interface Transport;
	uses interface Hashmap<socket_store_t*> as sockets;
}
implementation
{
	socket_t nextSock;
	socket_addr_t nextAddr;

	void start();
	socket_t socket();
	error_t bind(socket_t fd, socket_addr_t *addr);
	socket_t accept(socket_t fd);
	uint16_t write(socket_t fd, uint8_t *buff, uint16_t bufflen);
	error_t receive(pack* package);
	uint16_t read(socket_t fd, uint8_t *buff, uint16_t bufflen);
	error_t connect(socket_t fd, socket_addr_t * addr);
	error_t close(socket_t fd);
	error_t release(socket_t fd);
	error_t listen(socket_t fd);

	command void Transport.start()
	{
		socket_store_t defaultlistener;
		dbg(GENERAL_CHANNEL,"Configuring Transport \n");
		nextSock=0;
		nextAddr.port=ROOT_SOCKET_PORT;
		nextAddr.addr=ROOT_SOCKET_ADDR;
		defaultlistener.state=CLOSED;
		call sockets.insert(80,&defaultlistener);
		call Transport.listen((socket_t)80);

	}

	command socket_t Transport.socket()
	{
		int i;
		uint32_t*keys;
		dbg(GENERAL_CHANNEL,"aquiring a socket \n");
		if(call sockets.size()>=MAX_NUM_OF_SOCKETS )
		{
			// check for a free socket
			for(i=0;i<MAX_NUM_OF_SOCKETS;i++)
			{
				keys=call sockets.getKeys();
				if((call sockets.get(keys[i]))->state== CLOSED)
				{
					dbg(GENERAL_CHANNEL,"Found closed socket, reusing \n");
					return (socket_t)(keys[i]);
				}
			}
			dbg(GENERAL_CHANNEL,"All Sockets occupied \n");
			return NULL;
		}
		dbg(GENERAL_CHANNEL,"Generating a new socket \n");
		return NULL;
	}

	command error_t Transport.bind(socket_t fd, socket_addr_t *addr)
	{
		if((call sockets.get(fd))->state==ESTABLISHED||(call sockets.get(fd))->state==SYN_SENT||(call sockets.get(fd))->state==SYN_RCVD)
		{
			dbg(GENERAL_CHANNEL,"Failure to bind, socket is currently occupied\n");
			return FAIL;
		}
		(call sockets.get(fd))->dest.port=addr->port;
		(call sockets.get(fd))->dest.addr=addr->addr;
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
	command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
	{
		return FAIL;
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
		dbg(GENERAL_CHANNEL,"Converting socket on port %d to listener \n", fd);
		if((call sockets.get(fd))->state!=CLOSED)
		{
			dbg(GENERAL_CHANNEL,"Failure to open listener, socket is currently occupied\n");
			return FAIL;
		}
		(call sockets.get(fd))->state=LISTEN;
		(call sockets.get(fd))->src=(socket_port_t)fd;
		(call sockets.get(fd))->dest.port=0;
		(call sockets.get(fd))->dest.addr=0;

	}
}