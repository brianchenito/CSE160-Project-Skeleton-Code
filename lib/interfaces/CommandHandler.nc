interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer();
   event void setTestClient(uint16_t destination, uint16_t destport,uint16_t messagesize);
   event void setAppServer();
   event void setAppClient();
   event void allChat(char* msg);
   event void whisper(uint8_t len, char* msg);
   event void printUsers();
   event void registerUser(char* username);
}
