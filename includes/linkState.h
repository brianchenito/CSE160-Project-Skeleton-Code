#ifndef __LINKSTATE_H__
#define __LINKSTATE_H__

enum
{
	LINKSTATE_MAX_NEIGHBORS=64,
	LINKSTATE_TTL=64,
};
typedef nx_struct linkState{
	nx_uint16_t seq;
	nx_uint16_t owner;
	nx_uint16_t neighborcount;
	nx_uint16_t neighbors[LINKSTATE_MAX_NEIGHBORS];
}linkState;

#endif