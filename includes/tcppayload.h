#ifndef __TCPPAYLOAD_H__
#define __TCPPAYLOAD_H__

enum 
{
	FLAG_SYN=1,
	FLAG_SYN_ACK=2,
	FLAG_ACK=3,
	FLAG_FRAME=4,
	FLAG_FIN=5,
	FLAG_ACK=6,

};
typedef nx_struct tcppayload
{
	nx_uint8_t flag;
	nx_uint16_t sourceport;
	nx_uint16_t destport;
	nx_uint16_t seq;
	nx_uint16_t ack;
	nx_uint16_t windowsize;
	nx_uint16_t data;

}tcppayload;
#endif