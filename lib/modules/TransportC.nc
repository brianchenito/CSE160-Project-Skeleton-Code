#include "../../includes/am_types.h"
#include "../../includes/socket.h"
#include "../../includes/tcppayload.h"

generic configuration TransportC()
{
  provides interface Transport;
}
implementation
{

  components new TransportP();
  Transport=TransportP.Transport;

  components new HashmapC(socket_store_t,MAX_NUM_OF_SOCKETS) as sockets;
  TransportP.sockets->sockets;

}