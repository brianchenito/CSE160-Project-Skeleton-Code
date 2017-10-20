#ifndef __PATHNODE_H__
#define __PATHNODE_H__
typedef nx_struct pathnode
{
	nx_uint16_t label;
	nx_uint16_t cost;
	nx_uint16_t parent;
}pathnode;
#endif
