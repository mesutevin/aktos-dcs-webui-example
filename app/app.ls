
require! {
  './prelude': {
    flatten,
    initial,
    drop,
    join,
    concat,
    tail,
    head,
    map,
    zip,
    split,
    union
  }
}
/* initialize socket.io connections */
url = window.location.href
arr = url.split "/"
addr_port = arr.0 + "//" + arr.2
socketio-path = [''] ++ (initial (drop 3, arr)) ++ ['socket.io']
socketio-path = join '/' socketio-path
socket = io.connect addr_port, path: socketio-path
## debug
#console.log 'socket.io path: ', addr_port,  socketio-path
#console.log "socket.io socket: ", socket


# -----------------------------------------------------
# aktos-dcs livescript
# -----------------------------------------------------
envelp = (msg, msg-id) ->
  msg-raw = do
    sender: []
    timestamp: Date.now! / 1000
    msg_id: msg-id  # {{.actor_id}}.{{serial}}
    payload: msg
  return msg-raw

get-msg-body = (msg) ->
  subject = [subj for subj of msg.payload][0]
  #console.log "subject, ", subject
  return msg.payload[subject]



class ActorBase
  ~>
    @actor-id = uuid4!

  receive: (msg) ->
    #console.log @name, " received: ", msg.text

  recv: (msg) ->
    @receive msg
    try
      subjects = [subj for subj of msg.payload]
      for subject in subjects
        this['handle_' + subject] msg
    catch
      #console.log "problem in handler: ", e



# make a singleton
class ActorManager
  instance = null
  ~>
    instance ?:= SingletonClass!
    return instance

  class SingletonClass extends ActorBase
    ~>
      super ...
      @actor-list = []
      #console.log "Manager created with id:", @actor-id

    register: (actor) ->
      @actor-list = @actor-list ++ [actor]

    inbox-put: (msg) ->
      msg.sender ++= [@actor-id]
      for actor in @actor-list
        if actor.actor-id not in msg.sender
          #console.log "forwarding msg: ", msg
          actor.recv msg


class Actor extends ActorBase
  (name) ~>
    super ...
    @mgr = ActorManager!
    @mgr.register this
    @actor-name = name
    #console.log "actor \'", @name, "\' created with id: ", @actor-id
    @msg-serial-number = 0

  send: (msg) ->
    msg = envelp msg, @get-msg-id!
    @send_raw msg

  send_raw: (msg_raw) ->
    msg_raw.sender ++= [@actor-id]
    @mgr.inbox-put msg_raw


  get-msg-id: ->
    msg-id = @actor-id + '.' + String @msg-serial-number
    @msg-serial-number += 1
    return msg-id

class ProxyActor
  instance = null
  ~>
    instance ?:= SingletonClass!
    return instance

  class SingletonClass extends Actor
    ~>
      super ...
      #console.log "Proxy actor is created with id: ", @actor-id

      @socket = socket
      # send to server via socket.io
      @socket.on 'aktos-message', (msg) ~>
        try
          @network-rx msg
        catch
          console.log "Problem with receiving message: ", e

      @socket.on "connect", !~>
        #console.log "proxy actor says: connected=", @connected
        # update io on init
        @network-tx envelp UpdateIoMessage: {}, @get-msg-id!
        @send Connected: {}

      @socket.on "disconnect", !~>
        #console.log "proxy actor says: connected=", @connected
        @send Disconnected: {}


    network-rx: (msg) ->
      # receive from server via socket.io
      # forward message to inner actors
      console.log "proxy actor got network message: ", msg
      @send_raw msg

    receive: (msg) ->
      @network-tx msg

    network-tx: (msg) ->
      # receive from inner actors, forward to server
      msg.sender ++= [@actor-id]
      #console.log "emitting message: ", msg
      @socket.emit 'aktos-message', msg

# -----------------------------------------------------
# end of aktos-dcs livescript
# -----------------------------------------------------
/*

# aktos widget library

## basic types:

toggle-switch: toggles on every tap or click
push-button : toggles while clicking or tapping
status-led : readonly of toggle-switch or push-button

*/

class SwitchActor extends Actor
  (pin-name)~>
    super ...
    @callback-functions = []
    @pin-name = String pin-name
    @actor-name = @pin-name

  add-callback: (func) ->
      @callback-functions ++= [func]

  handle_IoMessage: (msg) ->
    msg-body = get-msg-body msg
    if msg-body.pin_name is @pin-name
      #console.log "switch actor got IoMessage: ", msg
      @fire-callbacks msg-body

  fire-callbacks: (msg) ->
    #console.log "fire-callbacks called!", msg
    for func in @callback-functions
      func msg

  gui-event: (val) ->
    #console.log "gui event called!", val
    @fire-callbacks do
      pin_name: @pin-name
      val: val

    @send IoMessage: do
      pin_name: @pin-name
      val: val


get-ractive-variable = (jquery-elem, ractive-variable) ->
  ractive-node = Ractive.get-node-info jquery-elem.get 0
  value = (app.get ractive-node.\keypath)[ractive-variable]
  #console.log "ractive value: ", value
  return value

set-ractive-variable = (jquery-elem, ractive-variable, value) ->
  ractive-node = Ractive.get-node-info jquery-elem.get 0
  app.set ractive-node.\keypath + '.' + ractive-variable, value

# ---------------------------------------------------
# END OF LIBRARY FUNCTIONS
# ---------------------------------------------------

# Create the actor which will connect to the server
ProxyActor!

# Set Ractive.DEBUG to false when minified:
Ractive.DEBUG = /unminified/.test !->
  /*unminified*/

# Initialize Ractive instance
app = new Ractive do
  template: '#app'
  el: 'container'

set-switch-actors = !->
  $ '.switch-actor' .each !->
    elem = $ this
    pin-name = get-ractive-variable elem, 'pin_name'
    actor = SwitchActor pin-name
    elem.data \actor, actor

set-switch-buttons = !->
  $ '.switch-button' .each !->
    elem = $ this
    actor = elem.data \actor

    # make it work without toggle-switch
    # visualisation
    elem.change ->
      actor.gui-event this.checked
    actor.add-callback (msg) ->
      elem.prop 'checked', msg.val

set-push-buttons = ->
  #
  # TODO: tapping works as doubleclick (two press and release)
  #       fix this.
  #
  $ '.push-button' .each ->
    elem = $ this
    actor = elem.data \actor

    # desktop support
    elem.on 'mousedown' ->
      actor.gui-event on
      elem.on 'mouseleave', ->
        actor.gui-event off
    elem.on 'mouseup' ->
      actor.gui-event off
      elem.off 'mouseleave'

    # touch support
    elem.on 'touchstart' (e) ->
      actor.gui-event on
      elem.touchleave ->
        actor.gui-event off
      e.stop-propagation!
    elem.on 'touchend' (e) ->
      actor.gui-event off


    actor.add-callback (msg) ->
      #console.log "push button got message: ", msg
      if msg.val
        elem.add-class 'button-active-state'
      else
        elem.remove-class 'button-active-state'

set-status-leds = ->
  $ '.status-led' .each ->
    elem = $ this
    actor = elem.data \actor
    actor.add-callback (msg) ->
      #console.log "status led: ", actor.pin-name, msg.val
      set-ractive-variable elem, 'val', msg.val

set-analog-displays = ->
  $ \.analog-display .each ->
    elem = $ this
    channel-name = get-ractive-variable elem, 'pin_name'
    #console.log "this is channel name: ", channel-name
    actor = SwitchActor channel-name
    actor.add-callback (msg) ->
      set-ractive-variable elem, 'val', msg.val

make-jq-mobile-connections = !->
  $ \document .ready ->
    $ '.ui-checkbox' .each !->
      elem = $ this
      actor = elem.children \.switch-actor .data \actor

      jq-button = elem.children \.ui-btn
      actor.add-callback (msg) ->
        if msg.val
          jq-button.add-class 'ui-checkbox-on'
          jq-button.add-class 'ui-btn-active'
          jq-button.remove-class 'ui-checkbox-off'
        else
          jq-button.remove-class 'ui-checkbox-on'
          jq-button.remove-class 'ui-btn-active'
          jq-button.add-class 'ui-checkbox-off'

    $ \.ui-flipswitch .each ->
      elem = $ this
      actor = elem.children \.switch-actor .data \actor
      actor.add-callback (msg) ->
        if msg.val
          elem.add-class 'ui-flipswitch-active'
        else
          elem.remove-class 'ui-flipswitch-active'

    $ \.push-button .each ->
      elem = $ this
      actor = elem.data \actor
      actor.add-callback (msg) ->
        #console.log "push button got message: ", msg.val
        if msg.val
          elem.add-class 'ui-btn-active'
        else
          elem.remove-class 'ui-btn-active'

      elem.disable-selection!
      elem.onselectstart = ->
        false
      elem.unselectable = "on"
      elem.css '-moz-user-select', 'none'
      elem.css '-webkit-user-select', 'none'

    # jQuery Sliders
    set-sliders = !->
      $ '.slider' .each !->
        elem = $ this .find 'input'
        actor = $ this .data \actor
        elem.on \change, ->
          #console.log "elem.val: ", elem.val!
          actor.gui-event elem.val!
        actor.add-callback (msg)->
          elem.val msg.val .slider \refresh

    set-sliders!


make-toggle-switch-visualisation = ->
  $ \.toggle-switch .each !->
    elem = $ this
    actor = elem.data \actor

    s = new ToggleSwitch elem.get 0, 'on', 'off'
    actor.add-callback (msg) ->
      # prevent switch callback call on
      # external events. only change visual status.
      tmp = s.f-callback
      s.f-callback = null
      if msg.val
        s.on!
      else
        s.off!
      s.f-callback = tmp
      tmp = null

    s.add-listener (state) !->
      actor.send-event state


app.on 'complete', !->
  #console.log "ractive completed, post processing other widgets..."
  # create actors
  set-switch-actors!
  # make bare widgets work
  set-switch-buttons!
  set-push-buttons!
  set-status-leds!
  set-analog-displays!
  # DO JQUERY SETTINGS IN THAT FUNCTION!
  # make extra visualization settings
  make-jq-mobile-connections!
  #make-toggle-switch-visualisation!



socket.on "connect", !->
  app.set "connected", true

socket.on 'disconnect', !->
  console.log 'disconnected...'
  app.set 'connected', false
