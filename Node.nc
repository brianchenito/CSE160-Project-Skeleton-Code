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
#include "includes/protocol.h"
#include "includes/linkState.h"
#include "includes/pathnode.h"

enum{REFRESHINTERVAL=50000};

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface Hashmap<uint16_t> as neighborIDs;
   uses interface Hashmap<linkState> as adjacentmap;

   uses interface Timer<TMilli> as periodicTimer;

   uses interface List<pathnode> as confirmed;
   uses interface List<pathnode> as tentative;
}

implementation{
   pack sendPackage;
   uint16_t LSPseq;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void informNeighbors();
   void findNeighbors();
   void recieveLinkState(uint16_t ttl,uint16_t src, uint16_t dest,void* payload,uint16_t payloadseq);
   void receivePing(uint16_t src, uint16_t dest, void* payload);
   uint16_t nextHop(uint16_t dest);
   void recivePingReply(uint16_t src);

   event void Boot.booted(){
      call AMControl.start();
      LSPseq=0;
      findNeighbors();
      call periodicTimer.startPeriodic( 10000 );
      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      //dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         linkState unpacked;
         // run protocol specific commands
         switch(myMsg->protocol){
            case PROTOCOL_PING:
               receivePing(myMsg->src, myMsg->dest, myMsg->payload);
               break;
            case PROTOCOL_PINGREPLY:
               recivePingReply(myMsg->src);
               break;
            case PROTOCOL_LINKEDSTATE:
               recieveLinkState(myMsg->TTL,myMsg->src,myMsg->dest,myMsg->payload,myMsg->seq);
               break;
         }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void periodicTimer.fired(){
      if((rand() % 10)>5)return;
      //dbg(GENERAL_CHANNEL, "FIRING PERIODIC \n");
      findNeighbors(); 
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      if(call neighborIDs.contains(destination)){// send directly to target
         call Sender.send(sendPackage, destination);
      }
      else {
         destination= nextHop(destination);
         dbg(ROUTING_CHANNEL, "Rerouting node to %d\n",destination );
         call Sender.send(sendPackage,destination);
      }
   }

   event void CommandHandler.printNeighbors(){
      uint32_t*keys;
      int i;
      dbg(GENERAL_CHANNEL, "dumping \n");

      keys=call neighborIDs.getKeys();
      for(i=0;i<call neighborIDs.size();i++){
         dbg(NEIGHBOR_CHANNEL, "\t%" PRIu16 "\n", keys[i]);
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
      if (payload!=NULL)memcpy(Package->payload, payload, length);
   }

   // clear neighbor list and ping adjacent nodes
   void findNeighbors(){
      int i;
      uint32_t*keys;
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_PING, 0, NULL, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      keys=call neighborIDs.getKeys();
      for(i=0;i<call neighborIDs.size();i++){
         if(call neighborIDs.get(keys[i])+REFRESHINTERVAL<call periodicTimer.getNow()){
            dbg(GENERAL_CHANNEL, "neighbor  %d has decayed \n", keys[i]);
            call neighborIDs.remove(keys[i]);
         }
      }
   }

   // create initial link state payload using neighbor ids
   void informNeighbors(){
      int i;
      linkState state;
      uint32_t*keys=call neighborIDs.getKeys();
      state.seq=LSPseq;// identifying version of lsp 
      LSPseq++;

      state.owner=TOS_NODE_ID;
      state.neighborcount=call neighborIDs.size();
      for(i=0;i<call neighborIDs.size();i++){
         state.neighbors[i]=keys[i];
      }

      //linkstate ttl decays per propagate, packet seq iterates, lspseq remains the same( versioning)
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, LINKSTATE_TTL, PROTOCOL_LINKEDSTATE, 0, &state, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }
   
   // flood linkstate to adjacent nodes
   void recieveLinkState(uint16_t ttl, uint16_t src, uint16_t dest,void* payload,uint16_t payloadseq){
      int i;
      uint32_t* arr;
      int j;
      linkState orig;// unpacked version of the old lps
      linkState* unpacked; // unpacked version of new lps
      unpacked= (linkState*)payload;
      dbg(ROUTING_CHANNEL, "-------received lps with  %d entries of origin %d, from step %d. version %d, ttl %d \n", unpacked->neighborcount, unpacked->owner,src, unpacked->seq,ttl);

      orig=(call adjacentmap.get(unpacked->owner));
      if(unpacked->owner!=TOS_NODE_ID&&(!call adjacentmap.contains(unpacked->owner)||(unpacked->seq>=orig.seq))){
         dbg(ROUTING_CHANNEL, "updating lps of %d with  %d entries \n",unpacked->owner, unpacked->neighborcount);
         call adjacentmap.remove(unpacked->owner);
         call adjacentmap.insert(unpacked->owner, *unpacked);
      }
      /*print awareness of other nodes for this node*/
      arr=call adjacentmap.getKeys();
      for(i=0;i<call adjacentmap.size();i++){
         dbg(ROUTING_CHANNEL,"Current awareness of: %d\n",arr[i] );
         orig=call adjacentmap.get(arr[i]);
         for(j=0;j<orig.neighborcount;j++){
            dbg(ROUTING_CHANNEL,"\t adjacent to  %d\n",orig.neighbors[j] );
         }
      }
      dbg(ROUTING_CHANNEL,"aware of the status of %d other nodes\n",i );

      if(ttl>0){

         arr=call neighborIDs.getKeys();
         for(i=0;i<call neighborIDs.size();i++){
            if (arr[i]!= unpacked->owner&&arr[i]!=src){
               dbg(ROUTING_CHANNEL, "node %d re propagating lps from root  %d to %d, %d\n",TOS_NODE_ID, unpacked->owner,arr[i],ttl);
               makePack(&sendPackage, TOS_NODE_ID, arr[i], ttl-1, PROTOCOL_LINKEDSTATE, payloadseq+1,payload, PACKET_MAX_PAYLOAD_SIZE);
               call Sender.send(sendPackage, arr[i]);
            }
         }
      }
   }  

   // fire back a reply message to a ping, confirming a connection if addressed to all. otherwise, route to destination.
   void receivePing(uint16_t src, uint16_t dest, void* payload){
      uint16_t next;
      if (dest==AM_BROADCAST_ADDR){
         dbg(NEIGHBOR_CHANNEL, "Handshake request from : %d\n", src);

         //dbg(GENERAL_CHANNEL, "replying to flood-------: \n");
         if(call neighborIDs.contains(src)){
            call neighborIDs.remove(src);
            call neighborIDs.insert(src, call periodicTimer.getNow()); 
         }
         else{
            call neighborIDs.insert(src, call periodicTimer.getNow()); 
            informNeighbors();
         }
         makePack(&sendPackage, TOS_NODE_ID, src, 0, PROTOCOL_PINGREPLY, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
         call Sender.send(sendPackage, src);
         return;
      }
      //received
      if(dest==TOS_NODE_ID){
         dbg(GENERAL_CHANNEL, "####Packet Received at destination#### Payload: %s\n", payload);
         return;
      }
      //reroute
      dbg(ROUTING_CHANNEL, "pathing-------: \n");
      next=nextHop(dest);
      makePack(&sendPackage, src, dest, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, next);

   }

   uint16_t nextHop(uint16_t dest)
   {
      pathnode parent;
      pathnode temp;
      linkState l;
      bool b;
      int i;
      int j;
      pathnode k;
      uint32_t* arr;
      if(!call adjacentmap.contains(dest)){
         dbg(GENERAL_CHANNEL, "FAILURE TO GENERATE PATH\n");
         return TOS_NODE_ID;
      }
      while(!call tentative.isEmpty()){
         call tentative.popback();
      }
      while(!call confirmed.isEmpty()){
         call confirmed.popback();
      }
      // add initial node
      temp.label=TOS_NODE_ID;
      temp.cost=0;
      temp.parent=0;
      call confirmed.pushback(temp);
      arr=call neighborIDs.getKeys();

      //add neighbors of initial node 
      for(i=0;i<call neighborIDs.size();i++)
      {
         temp.label=arr[i];
         temp.cost=1;
         temp.parent=TOS_NODE_ID;
         call tentative.pushback(temp);
      }
      while(call tentative.size()>0)
      {
         //transfer first element of tent to conf
         parent=call tentative.popfront();
         call confirmed.pushback(parent);
         //precheck for full path
         if(parent.label==dest)
         {
            dbg(GENERAL_CHANNEL, "FOUND DESTINATION, CLEARING TENTATIVE\n");
            while(!call tentative.isEmpty()){
               call tentative.popback();
            }
            break;
         }
         l=call adjacentmap.get(parent.label);
         for(i=0;i<l.neighborcount;i++){
            b=FALSE;
            // check to make sure elements are not already queued
            for(j=0;j<call confirmed.size();j++){
               k=call confirmed.get(j);
               if(l.neighbors[i]==k.label){
                  b=TRUE;
                  break;
               }
            }
            for(j=0;j<call tentative.size();j++){
               k=call confirmed.get(j);
               if(l.neighbors[i]==k.label){
                  b=TRUE;
                  break;
               }
            }
            //add a new element to tentative;
            if (!b){
               temp.label=l.neighbors[i];
               temp.cost=parent.cost+1;
               temp.parent=parent.label;
               call tentative.pushback(temp);
            }
            
         }
      }
      if (parent.label==dest){
         dbg(GENERAL_CHANNEL, "PATH GENERATED, WORKING BACK TO DETERMINE NEXTHOP\n");
         j=dest;
         for(i=call confirmed.size()-1;i>=0;i--){
            temp=call confirmed.get(i);
            if (temp.label==j){
               dbg(GENERAL_CHANNEL,"\t %d\n",j);
               if(temp.parent==TOS_NODE_ID){
                  dbg(GENERAL_CHANNEL, "NEXTHOP: %d\n",j);
                  break;
               }
               j=temp.parent;
            }
         }
         return j;
      }
      dbg(GENERAL_CHANNEL, "PATH GENERATION FAILURE, FALLING BACK TO FLOODING\n");
      return AM_BROADCAST_ADDR;
   }


   // receive a ping from a neighbor and confirm connection.
   void recivePingReply(uint16_t src){
      dbg(NEIGHBOR_CHANNEL, "Hand shook with : %d\n", src);
      if(call neighborIDs.contains(src)){
         call neighborIDs.remove(src);
         call neighborIDs.insert(src, call periodicTimer.getNow());
      }
      else{
         call neighborIDs.insert(src, call periodicTimer.getNow()); 
         informNeighbors();
      }
   }
}
