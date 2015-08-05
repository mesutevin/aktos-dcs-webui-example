// Generated by LiveScript 1.4.0
(function(){
  var ref$, map, filter, tail, hapi, zmq, server, io, subSock, pubSock, serverId, messageHistory, aktosDcsFilter;
  ref$ = require('prelude-ls'), map = ref$.map, filter = ref$.filter, tail = ref$.tail;
  hapi = require("hapi");
  zmq = require('zmq');
  server = new hapi.Server();
  server.connection({
    port: 4000
  });
  io = require('socket.io')(server.listener);
  subSock = zmq.socket('sub');
  pubSock = zmq.socket('pub');
  pubSock.connect('tcp://127.0.0.1:5012');
  subSock.connect('tcp://127.0.0.1:5013');
  subSock.subscribe('');
  process.on('SIGINT', function(){
    subSock.close();
    pubSock.close();
    return console.log('Received SIGINT, zmq sockets are closed...');
  });
  serverId = "aaaaaaaaaaaaaaaa-server-aaaaaaaaaaaaaaa";
  messageHistory = [];
  aktosDcsFilter = function(msg){
    var i, now, timeout, treshold;
    if (in$(serverId, msg.sender)) {
      return null;
    }
    if (msg.cls === 'ProxyActorMessage') {
      return null;
    }
    if (in$(msg.msg_id, (function(){
      var i$, ref$, len$, results$ = [];
      for (i$ = 0, len$ = (ref$ = messageHistory).length; i$ < len$; ++i$) {
        i = ref$[i$];
        results$.push(i[0]);
      }
      return results$;
    }()))) {
      console.log("dropping duplicate message: ", msg);
      return null;
    }
    now = Date.now() / 1000 || 0;
    timeout = 10;
    treshold = now - timeout;
    messageHistory = messageHistory.concat([[msg.msg_id, msg.timestamp]]);
    console.log("message history: ", messageHistory);
    if (messageHistory[0]) {
      if (messageHistory[0][1] < treshold) {
        console.log("deleting ", now - messageHistory[0][1], " secs old message");
        messageHistory = tail(messageHistory);
      }
    }
    return msg;
  };
  io.on('connection', function(socket){
    console.log("new client connected, starting its forwarder...");
    socket.on("aktos-message", function(msg){
      console.log("aktos-message from browser: ", msg);
      msg.sender = msg.sender.concat([serverId]);
      socket.broadcast.emit('aktos-message', msg);
      return pubSock.send(JSON.stringify(msg));
    });
    return subSock.on('message', function(message){
      var msg;
      message = message.toString();
      msg = JSON.parse(message);
      msg = aktosDcsFilter(msg);
      if (msg) {
        msg.sender = msg.sender.concat([serverId]);
        socket.broadcast.emit('aktos-message', msg);
        return socket.emit('aktos-message', msg);
      }
    });
  });
  server.route({
    method: 'GET',
    path: '/',
    handler: {
      file: './public/index.html'
    }
  });
  server.route({
    method: 'GET',
    path: '/{filename*}',
    handler: {
      file: function(request){
        return './public/' + request.params.filename;
      }
    }
  });
  server.route({
    method: 'GET',
    path: '/static/{filename*}',
    handler: {
      file: function(request){
        return './public/' + request.params.filename;
      }
    }
  });
  server.start(function(){
    console.log("Server running at:", server.info.uri);
  });
  function in$(x, xs){
    var i = -1, l = xs.length >>> 0;
    while (++i < l) if (x === xs[i]) return true;
    return false;
  }
}).call(this);
