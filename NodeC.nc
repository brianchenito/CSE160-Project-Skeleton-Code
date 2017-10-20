/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/command.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/linkState.h"
#include "includes/pathnode.h"
configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components new HashmapC(uint16_t,100) as neighbors;
    Node.neighborIDs->neighbors;

    components new HashmapC(linkState,100) as adjMap;
    Node.adjacentmap->adjMap;

    components new TimerMilliC() as myTimerC; 
    Node.periodicTimer -> myTimerC;

    components new ListC(pathnode,100) as conf;
    Node.confirmed -> conf;

    components new ListC(pathnode,100) as tent;
    Node.tentative -> tent;


}
