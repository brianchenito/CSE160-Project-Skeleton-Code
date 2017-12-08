#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3
    CMD_TEST_SERVER=5
    CMD_TEST_CLIENT=4

    CMD_ALLCHAT=7
    CMD_WHISPER=8
    CMD_USER_DUMP=10
    CMD_USER_REGISTER=11

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in range(1, self.numMote+1):
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in range(1, self.numMote+1):
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in range(1, self.numMote+1):
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

    def setTestServer(self,destination):
        self.sendCMD(self.CMD_TEST_SERVER, destination, "test server command");
    
    def setTestClient(self,source,destination=1, destport=41, msgsz=14):

        self.sendCMD(self.CMD_TEST_CLIENT,source, "{0}{1}{2}".format(chr(destination),chr(destport), chr(msgsz)));

    def allChat(self, source, msg):
        self.sendCMD(self.CMD_ALLCHAT,source,"{0}".format(msg ))

    def whisper(self,source,dest,msg):
        length=len(dest)
        self.sendCMD(self.CMD_WHISPER,source,"{0}{1}{2}".format(chr(length),dest,msg))

    def dumpUsers(self,source):
        self.sendCMD(self.CMD_USER_DUMP, source)

    def RegisterUser(self, source, username):
        self.sendCMD(self.CMD_USER_REGISTER, source,"{0}".format(username ) )

def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("pizza.topo");
    s.loadNoise("meyer-heavy.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    #s.addChannel(s.TRANSPORT_CHANNEL);



    s.runTime(5);
    s.setTestServer(1);
    s.runTime(5);

    s.RegisterUser(2, "butts")
    s.runTime(5)
    #s.RegisterUser(4,"mcbutt")
    s.runTime(40)
    #s.allChat(2, "hihihi\n");
    
    s.runTime(40);
    #s.setTestClient(4);#client addr, serv addr, serv port, msgsize
    #s.whisper(2,"mcbutt", "hello, world");
    s.runTime(40);
    # s.ping(1,9,"hello");
    # s.runTime(20);

if __name__ == '__main__':
    main()
