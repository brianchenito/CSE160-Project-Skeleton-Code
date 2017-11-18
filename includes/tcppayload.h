#ifndef __TCPPAYLOAD_H__
#define __TCPPAYLOAD_H__

enum 
{
	FLAG_SYN=0x1,
	FLAG_ACK=0x2,
	FLAG_FIN=0x4,
};
typedef nx_struct tcpPayload
{
	nx_uint8_t flags;
	nx_uint16_t sourceport;
	nx_uint16_t destport;
	nx_uint16_t seq;
	nx_uint16_t ack;
	nx_uint16_t windowsize;

}tcpPayload;
#endif