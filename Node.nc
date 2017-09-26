/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "DefineMacros.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface List<uint16_t> as neighborIDs;

   uses interface Timer<TMilli> as periodicTimer; 
}

implementation{
   pack sendPackage;
   int i;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   bool isInNeighbors(uint16_t n);
   void findNeighbors();

   event void Boot.booted(){
      call AMControl.start();
      call periodicTimer.startPeriodic( 10000 );
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void periodicTimer.fired(){
      if((rand() % 100)>5)return;
      while (!call neighborIDs.isEmpty())
      {
         call neighborIDs.popback();
      }
      findNeighbors();
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         findNeighbors();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         
         if(myMsg->dest==TOS_NODE_ID)dbg(FLOODING_CHANNEL, "Package Payload Recieved at destination: %s\n", myMsg->payload);
         if(myMsg->protocol==_HANDSHAKEREQUEST)
         {
            makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 0, _HANDSHAKERESPOND, 0, "", PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, myMsg->src);
            return msg;
         }

         else if(myMsg->protocol==_HANDSHAKERESPOND)
         {
            if(!isInNeighbors(myMsg->src)) 
            {
               dbg(NEIGHBOR_CHANNEL, "Hand shook with : %d\n", myMsg->src);
               call neighborIDs.pushback(myMsg->src); 
               return msg;
            }
         }
         else if (myMsg->dest!=TOS_NODE_ID && myMsg->seq<_SEQMAX)
         {
            dbg(FLOODING_CHANNEL,  "flooded from %" PRIu16 " from %"PRIu16"\n",myMsg->src,TOS_NODE_ID );
            makePack(&sendPackage, TOS_NODE_ID, myMsg->dest, 0, _PACKET, myMsg->seq+1, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
         }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){
      dbg(NEIGHBOR_CHANNEL,"Neighbors:\n");
      for(i=0;i<call neighborIDs.size();i++)
      {
         dbg(NEIGHBOR_CHANNEL, "\t%" PRIu16 "\n", call neighborIDs.get(i));
      }
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
   bool isInNeighbors(uint16_t n)
   {
      for(i=0;i<call neighborIDs.size();i++)
      {

         if (call neighborIDs.get(i)==n)
         {
            return TRUE;
         }
      }
      return FALSE;
   }
   void findNeighbors()
   {
      //dbg(NEIGHBOR_CHANNEL, "Messaging potential neighbors\n");
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, _HANDSHAKEREQUEST, 0, "", PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }
}
