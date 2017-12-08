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
#include "includes/tcppayload.h"

enum{
   REFRESHINTERVAL=5000000,
   RETRANSMITINTERVAL=500000,
   CLOSEACK=65535
};

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface Transport;

   uses interface CommandHandler;

   uses interface Hashmap<uint16_t> as neighborIDs;
   uses interface Hashmap<linkState> as adjacentmap;

   uses interface Timer<TMilli> as periodicTimer;
   uses interface Timer<TMilli> as retryTimer;

   uses interface List<pathnode> as confirmed;
   uses interface List<pathnode> as tentative;

   uses interface List<pack> as inbox;
}

implementation{
   pack sendPackage;
   uint16_t emphport;
   uint16_t LSPseq;
   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   void informNeighbors();
   void findNeighbors();
   void recieveLinkState(uint16_t ttl,uint16_t src, uint16_t dest,void* payload,uint16_t payloadseq);
   void receivePing(uint16_t src, uint16_t dest, void* payload);
   uint16_t nextHop(uint16_t dest);
   void recivePingReply(uint16_t src);

   //TCP
   uint16_t acktrack;//servers acks sent
   uint16_t tentsend;// client tentative values sent
   uint16_t tentseq;
   uint16_t succsend;// client acks recieved
   uint16_t succseq;// client acks seq recieved
   uint16_t serverseq;//server seqs recieved
   uint16_t maxval;// client vals to send
   uint16_t tenttarget; // target node
   bool datasend;
   bool toclose;
   bool closed;
   uint16_t window; // sizeof send window
   tcppayload tentpayload;// tentative client send payload, sent on retry

   event void Boot.booted(){
      call AMControl.start();
      call Transport.start();
      LSPseq=0;
      acktrack=0;
      succsend=65535;
      datasend=FALSE;
      toclose=FALSE;
      closed=FALSE;

      window=5;
      emphport=ROOT_SOCKET_PORT;
      findNeighbors();
      call periodicTimer.startPeriodic( 5000 );
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
      uint16_t next;
      tcppayload* tcpunpack;
      tcppayload sendtcp;
      socket_store_t sockdata;
      socket_t socketid;
      socket_store_t socketinfo;
      socket_addr_t sockaddr;

      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
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
            case PROTOCOL_TCP:
            if(myMsg->dest==TOS_NODE_ID)
            {
               //dbg(GENERAL_CHANNEL, "TCP PACK RECIEVED BY DESTINATION\n");
               tcpunpack=myMsg->payload;
               if (closed)break;
                  //call Transport.receive(myMsg);
               switch(tcpunpack->flag){
                  case FLAG_SYN:
                     if(toclose||closed)break;
                     dbg(GENERAL_CHANNEL, "RECIEVED SYN, CHECKING FOR LISTENER SOCK \n");
                     sockaddr.addr=myMsg->src;
                     sockaddr.port=tcpunpack->sourceport;
                     socketid=call Transport.accept(call Transport.getSock(tcpunpack->destport),sockaddr );
                     if (socketid ==NULL){
                        dbg(GENERAL_CHANNEL, "ERROR,NO LISTENER AT SPECIFIED PORT: %d \n", tcpunpack->destport);
                        return msg;
                     }
                     dbg(GENERAL_CHANNEL, "SERVER ACCEPTED, FIRING BACK SYN ACK WITH SYNC DATA \n");
                     sendtcp.flag=FLAG_SYN_ACK;
                     sendtcp.sourceport=call Transport.getPort(socketid);
                     sendtcp.destport=tcpunpack->sourceport;
                     sendtcp.seq=rand() % 1000;
                     sendtcp.ack=0;
                     sendtcp.windowsize=window;

                     serverseq=sendtcp.seq;

                     next=nextHop(myMsg->src);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                     call Sender.send(sendPackage,next);

                     // retry
                     tentpayload=sendtcp;
                     tenttarget=myMsg->src;
                     call retryTimer.startOneShot(RETRANSMITINTERVAL);

                     break;
                  case FLAG_SYN_ACK:
                     if(toclose)break;
                     dbg(GENERAL_CHANNEL, "RECIEVED SYN_ACK, CHECKING FOR AND CONFIGURING CLIENT CONNECT \n");
                     sockdata=call Transport.getSockInfo(tcpunpack->destport);
                     if(sockdata.state!= SYN_SENT){
                        dbg(GENERAL_CHANNEL, "INVALID SYN_ACK RECIEVED, IGNORING \n");
                        break;
                     }
                     // stop retry
                     
                     succseq=tcpunpack->seq;
                     sockaddr.port=tcpunpack->sourceport;
                     sockaddr.addr=myMsg->src;
                     socketid=call Transport.getSock(tcpunpack->destport);
                     if((call Transport.establish(socketid,sockaddr))==FAIL)break;
                     call retryTimer.stop();
                     dbg(GENERAL_CHANNEL, "CONNECTED TO NODE %d AT PORT %d, FIRING BACK ACK \n", myMsg->src, tcpunpack->sourceport);
                     sendtcp.flag=FLAG_ACK;

                     sendtcp.sourceport=tcpunpack->destport;

                     sendtcp.destport=tcpunpack->sourceport;
                     sendtcp.ack=0;
                     sendtcp.seq=succseq+1;
                     sendtcp.windowsize=tcpunpack->windowsize;

                     next=nextHop(myMsg->src);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                     call Sender.send(sendPackage,next);
                     dbg(GENERAL_CHANNEL, "FIRED OFF FINAL HANDSHAKE ACK TO NODE %d, PORT %d\n",myMsg->src,sendtcp.destport);
                     tentpayload=sendtcp;
                     tenttarget=myMsg->src;
                     call retryTimer.startOneShot(RETRANSMITINTERVAL);

                     break;
                  case FLAG_ACK:
                     if(toclose&&tcpunpack->ack==CLOSEACK ){
                        call retryTimer.stop();
                        dbg(GENERAL_CHANNEL, "CLOSING CONNECTION ON PORT %d TO NODE %d ON PORT %d\n",tcpunpack->destport,myMsg->src, tcpunpack->sourceport);
                        call Transport.close(call Transport.getSock(tcpunpack->destport)); /////////
                        closed=TRUE;
                     }
                     //dbg(GENERAL_CHANNEL, "RECIEVED ACK \n");
                     socketid=call Transport.getSock(tcpunpack->sourceport);
                     
                     if (tcpunpack->ack==0&&(call Transport.getSock(80))!=0){// FOR SERVER
                        dbg(GENERAL_CHANNEL, "RECIEVED HANDSHAKE ACK \n");
                        sockaddr.port=tcpunpack->sourceport;
                        sockaddr.addr=myMsg->src;
                        socketid=call Transport.getSock(tcpunpack->destport);
                        if(call Transport.establish(socketid,sockaddr)!=FAIL&&(serverseq+1)==tcpunpack->seq)
                        {
                           serverseq++;
                           call retryTimer.stop();// stop retry

                           dbg(GENERAL_CHANNEL, "SERVER FIRING FIRST ACK \n");
                           sendtcp.flag=FLAG_ACK;
                           sendtcp.sourceport=tcpunpack->destport;
                           sendtcp.destport=tcpunpack->sourceport;
                           sendtcp.seq=serverseq;
                           sendtcp.ack=0;
                           sendtcp.windowsize=tcpunpack->windowsize;
                           sendtcp.data=0;
                           next=nextHop(myMsg->src);
                           makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                           call Sender.send(sendPackage,next);

                           tenttarget=myMsg->src;
                           tentpayload=sendtcp;
                           call retryTimer.startOneShot(RETRANSMITINTERVAL);

                           break;
                        }
                        dbg(GENERAL_CHANNEL, "RECIEVED INVALID HANDSHAKE ACK.\n");
                        break;
                     }
                     if(socketid==NULL){
                        dbg(GENERAL_CHANNEL, "INVALID ACK RECIEVED FROM %d, PORT %d, IGNORING \n",myMsg->src,tcpunpack->sourceport);
                        break;
                     }
                     else if(tcpunpack->ack==(succsend+1)&& tcpunpack->ack!=CLOSEACK){
                        call retryTimer.stop();
                        succsend++;
                        succseq=tcpunpack->seq;
                        dbg(GENERAL_CHANNEL, "---- RECIEVED INORDER ACK %d ----\n",tcpunpack->ack);
                        if(tentsend<maxval)
                        {
                           sendtcp.flag=FLAG_FRAME;
                           tentsend++;
                           tentseq++;
                           sendtcp.sourceport=tcpunpack->destport;
                           sendtcp.destport=tcpunpack->sourceport;
                           sendtcp.data=tentsend;
                           sendtcp.seq=tentseq;
                           sendtcp.ack=succsend;
                           tentpayload=sendtcp;
                           tenttarget=myMsg->src;
                           next=nextHop(myMsg->src);
                           dbg(GENERAL_CHANNEL, "TRANSMITTING DATA %d\n",tentsend);
                           makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                           call Sender.send(sendPackage,next);

                           call retryTimer.startOneShot(RETRANSMITINTERVAL);
                        }
                        else if(tcpunpack->ack>=maxval)
                        {
                           dbg(GENERAL_CHANNEL, "---- RECIEVED ALL ACKS, READY TO CLOSE ----\n");
                           call retryTimer.stop();
                           toclose=TRUE;
                           sendtcp.sourceport=tcpunpack->destport;
                           sendtcp.destport=tcpunpack->sourceport;
                           sendtcp.flag=FLAG_FIN;

                           tentpayload=sendtcp;
                           tenttarget=myMsg->src;
                           next=nextHop(myMsg->src);

                           dbg(GENERAL_CHANNEL, "TRANSMITTING FIN \n");
                           makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                           call Sender.send(sendPackage,next);
                           call retryTimer.startOneShot(RETRANSMITINTERVAL);



                        }
                      


                     }
                     else if (succsend==65535&&tcpunpack->ack==0)
                     {
                        succsend=0;
                        succseq=tcpunpack->seq;
                        call retryTimer.stop();
                        dbg(GENERAL_CHANNEL, "---- RECIEVED INITIAL INORDER ACK,STARTING DATA STREAM ----\n");
                        datasend=TRUE;
                        sendtcp.flag=FLAG_FRAME;
                        sendtcp.sourceport=tcpunpack->destport;
                        sendtcp.destport=tcpunpack->sourceport;
                        sendtcp.seq=tcpunpack->seq+1;
                        sendtcp.ack=0;
                        sendtcp.data=1;


                        dbg(GENERAL_CHANNEL, "STARTING DATA FIRE\n");
                        tentpayload=sendtcp;
                        tenttarget=myMsg->src;
                        call retryTimer.startOneShot(0);

                     }
                     else if(succsend<maxval)
                     {
                        dbg(GENERAL_CHANNEL, "RECIEVED OUT OF ORDER ACK,%d, expected  %d \n",tcpunpack->ack, succsend+1);
                        if(tcpunpack->ack>succsend)succsend=tcpunpack->ack;
                        if(tcpunpack->ack<maxval)call retryTimer.startOneShot(0);
                        
                     }
                     break;
                  case FLAG_FRAME:
                     call retryTimer.stop();
                     dbg(GENERAL_CHANNEL,"RECIEVED FRAME\n");
                     if(tcpunpack->seq==(serverseq+1)){
                        dbg(GENERAL_CHANNEL, "----\tRECIEVED INORDER FRAME WITH DATA '%d' \t----############ \n\t\t\t\t\tseq: %d\tack: %d\n", tcpunpack->data,tcpunpack->seq,acktrack);
                        serverseq++;
                        acktrack++;
                        succsend=tcpunpack->ack;
                        sendtcp.flag=FLAG_ACK;
                        sendtcp.sourceport=tcpunpack->destport;
                        sendtcp.destport=tcpunpack->sourceport;
                        sendtcp.seq=tcpunpack->seq;
                        sendtcp.ack=acktrack;
                        sendtcp.windowsize=window;
                        sendtcp.data=0;
                        tentpayload=sendtcp;
                        tenttarget=myMsg->src;
                        dbg(GENERAL_CHANNEL, "FIRING BACK ACK%d, port %d \n", acktrack,sendtcp.sourceport);

                        next=nextHop(myMsg->src);
                        makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                        call Sender.send(sendPackage,next);
                        call retryTimer.startOneShot(RETRANSMITINTERVAL);

                     }
                     else{
                        dbg(GENERAL_CHANNEL, "RECIEVED OUT OF ORDER FRAME WITH DATA %d  (expected seq: %d, actual: %d)\n", tcpunpack->data,serverseq+1,tcpunpack->seq);
                        sendtcp.flag=FLAG_ACK;
                        sendtcp.sourceport=tcpunpack->destport;
                        sendtcp.destport=tcpunpack->sourceport;
                        sendtcp.seq=tcpunpack->seq;
                        sendtcp.ack=acktrack;
                        sendtcp.windowsize=window;
                        sendtcp.data=0;
                        dbg(GENERAL_CHANNEL, "FIRING BACK ACK OF MOST RECENT CONFIRM %d, port%d \n", acktrack,sendtcp.sourceport);

                        next=nextHop(myMsg->src);
                        makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                        call Sender.send(sendPackage,next);                        
                     }
                     break;
                  case FLAG_FIN:
                     call retryTimer.stop();
                     dbg(GENERAL_CHANNEL, "RECIEVED FIN, FIRING BACK FIN ACK \n");
                     sendtcp.flag=FLAG_FIN_ACK;
                     sendtcp.sourceport=tcpunpack->destport;
                     sendtcp.destport=tcpunpack->sourceport;

                     next=nextHop(myMsg->src);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                     call Sender.send(sendPackage,next);

                     dbg(GENERAL_CHANNEL, "CLOSING CONNECTION ON PORT %d TO NODE %d ON PORT %d\n",tcpunpack->destport,myMsg->src, tcpunpack->sourceport);
                     call Transport.close(call Transport.getSock(tcpunpack->destport));
                     closed=TRUE;


                     break;
                  case FLAG_FIN_ACK:
                     call retryTimer.stop();
                     dbg(GENERAL_CHANNEL, "RECIEVED FIN_ACK, FIRING FINAL ACK \n");
                     sendtcp.flag=FLAG_ACK;
                     sendtcp.sourceport=tcpunpack->destport;
                     sendtcp.destport=tcpunpack->sourceport;
                     sendtcp.ack=CLOSEACK;
                     tentpayload=sendtcp;
                     tenttarget=myMsg->src;

                     next=nextHop(myMsg->src);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src,0,PROTOCOL_TCP,0,(uint8_t*)&sendtcp,PACKET_MAX_PAYLOAD_SIZE );
                     call Sender.send(sendPackage,next);
                     dbg(GENERAL_CHANNEL, "CLOSING CONNECTION ON PORT %d TO NODE %d ON PORT %d\n",tcpunpack->destport,myMsg->src, tcpunpack->sourceport);
                     call Transport.close(call Transport.getSock(tcpunpack->destport));
                     closed=TRUE;
                     break;
                  default:
                         dbg(GENERAL_CHANNEL, "RECIEVED INVALID FLAG\n");
                         break;
               }
            }
            else
            {
               next=nextHop(myMsg->dest);
               //dbg(GENERAL_CHANNEL, "TCP PACK RETRANSMITTING TO %d \n",next);
               call Sender.send(*myMsg, next);// MAYBE FIX
            }
            break;   

         }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void periodicTimer.fired(){

      if((rand() % 10)>2)return;
      dbg(FLOODING_CHANNEL, "FIRING PERIODIC \n");
      findNeighbors(); 
   }
   // resend message
   event void retryTimer.fired(){
      uint16_t next;
      uint16_t seq;
      
     
      next=nextHop(tenttarget);
      if(!datasend)
      {
         dbg(GENERAL_CHANNEL, "TIMEOUT, RESENDING\n");
         makePack(&sendPackage, TOS_NODE_ID,tenttarget,0,PROTOCOL_TCP,0,(uint8_t*)&tentpayload,PACKET_MAX_PAYLOAD_SIZE );
         call Sender.send(sendPackage,next);
      }
      else// stream over as much data as the window will allow, starting from the last acked data
      {
         tentsend=succsend;
         tentseq=succseq;
         while(tentsend<=(succsend+window)&&tentsend<maxval)
         {
            tentsend++;
            tentseq++;
            tentpayload.data=tentsend;
            tentpayload.seq=tentseq;
            tentpayload.ack=succsend;
            dbg(GENERAL_CHANNEL, "TRANSMITTING DATA %d\n",tentsend);
            makePack(&sendPackage, TOS_NODE_ID,tenttarget,0,PROTOCOL_TCP,0,(uint8_t*)&tentpayload,PACKET_MAX_PAYLOAD_SIZE );
            call Sender.send(sendPackage,next);

         }
      }
      call retryTimer.startOneShot(RETRANSMITINTERVAL);



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

   event void CommandHandler.setTestServer(){

      socket_t listener;
      socket_addr_t listen_addr;

      dbg(GENERAL_CHANNEL, "converting to test server \n");

      listen_addr.port=80;
      listen_addr.addr=TOS_NODE_ID;
      
      listener= call Transport.socket();
      if (listener==NULL){
         dbg(GENERAL_CHANNEL, "FAILURE TO GET SOCKET\n");
         return;
      }
      
      if(call Transport.bind(listener,listen_addr)==FAIL){
         dbg(GENERAL_CHANNEL, "FAILURE TO BIND\n");
         return;
      }

      if(call Transport.listen(listener)==FAIL){
         dbg(GENERAL_CHANNEL, "FAILURE TO SET AS LISTENER\n");
         return;
      }
      dbg(GENERAL_CHANNEL, "------Successful setup of test server \n");
   }

   event void CommandHandler.setTestClient(uint16_t destination, uint16_t destport,uint16_t messagesize){
      uint16_t next;
      socket_t fd;
      socket_addr_t fd_addr;
      socket_addr_t dest_addr;
      tcppayload payload;

      dest_addr.port=destport;
      dest_addr.addr=destination;

      maxval=messagesize;

      dbg(GENERAL_CHANNEL, "converting to test client and messaging target node %d on port %d \n",destination,destport);

      fd_addr.port=emphport;
      emphport+=1;
      fd_addr.addr=TOS_NODE_ID;
      fd= call Transport.socket();
      if(fd==NULL){
         dbg(GENERAL_CHANNEL, "FAILURE TO GET SOCKET\n");
         return;
      }

      if(call Transport.bind(fd,fd_addr)==FAIL){
         dbg(GENERAL_CHANNEL, "BIND FAILURE\n");
         return;
      }
      dbg(GENERAL_CHANNEL, "-----client ready to begin handshake\n");
      payload= call Transport.connect(fd,dest_addr ); 
      next=nextHop(dest_addr.addr);
      makePack(&sendPackage, TOS_NODE_ID,dest_addr.addr,0,PROTOCOL_TCP,0,(uint8_t*)&payload,PACKET_MAX_PAYLOAD_SIZE );
      dbg(GENERAL_CHANNEL, "TCP SYN FIRING TO %d\n",next);
      call Sender.send(sendPackage,next );
      // setting up retry
      tentpayload=payload;
      tenttarget=dest_addr.addr;
      call retryTimer.startOneShot(RETRANSMITINTERVAL);
   }

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
            dbg(ROUTING_CHANNEL, "neighbor  %d has decayed \n", keys[i]);
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

         dbg(FLOODING_CHANNEL, "replying to flood-------: \n");
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
         dbg(ROUTING_CHANNEL, "FAILURE TO GENERATE PATH\n");
         return AM_BROADCAST_ADDR;
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
            dbg(ROUTING_CHANNEL, "FOUND DESTINATION, CLEARING TENTATIVE\n");
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
         dbg(ROUTING_CHANNEL, "PATH GENERATED, WORKING BACK TO DETERMINE NEXTHOP\n");
         j=dest;
         for(i=call confirmed.size()-1;i>=0;i--){
            temp=call confirmed.get(i);
            if (temp.label==j){
               dbg(ROUTING_CHANNEL,"\t %d\n",j);
               if(temp.parent==TOS_NODE_ID){
                  dbg(ROUTING_CHANNEL, "NEXTHOP: %d\n",j);
                  break;
               }
               j=temp.parent;
            }
         }
         return j;
      }
      dbg(ROUTING_CHANNEL, "PATH GENERATION FAILURE, FALLING BACK TO FLOODING\n");
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
