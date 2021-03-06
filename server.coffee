server = exports

HOST = "localhost"
PORT = 8001

MESSAGE_BACKLOG = 200
SESSION_TIMEOUT = 60 * 1000

server.init = (fake = { }) ->

  sys = fake.sys or require "sys"
  router = fake.router or require("./lib/node-router")
  server = router.getServer()

  qs = fake.qs or require "querystring"
  url = fake.url or require "url"

  process = fake.process or global.process

  sessions = {} 

  channel = new ->

    messages = []
    callbacks = []

    @appendMessage = (nick, type, text) ->
      m =
        nick: nick
        type: type
        text: text
        timestamp: (new Date).getTime()
      
      switch type
        when "msg"  then sys.puts "<#{nick}> #{text}"
        when "join" then sys.puts "#{nick} joined"
        when "part" then sys.puts "#{nick} part"

      messages.push m

      callbacks.shift().callback [m] while callbacks.length > 0

      messages.shift() while messages.length > MESSAGE_BACKLOG
    
    @query = (since, callback) -> 

      matching = []
      matching.push message for message in messages when message.timestamp > since

      if matching.length isnt 0
        callback matching 
      else
        callbacks.push timestamp: new Date, callback: callback

    clearCallbacks = () ->
      now = new Date
      while callbacks.length > 0 and now - callbacks[0].timestamp > 30 * 1000
        callbacks.shift().callback [] 

    # Let old callbacks hang around for up to 30 seconds
    setInterval clearCallbacks, 3000

    this

  createSession = (nick) ->
    if nick.length > 50 then return null
    if /[^\w_\-^!]/.exec nick then return null

    for id of sessions
      if sessions[id]?.nick is nick 
        return null

    session =
      nick: nick
      id : Math.floor(Math.random() * 999999999999).toString()
      timestamp: new Date

      poke: -> session.timestamp = new Date

      destroy: ->
        channel.appendMessage session.nick, "part"
        delete sessions[session.id]

    sessions[session.id] = session
    session

  killOldSessions = ->
    now = new Date
    for session of sessions 
      if now - session.timestamp > SESSION_TIMEOUT
        session.destroy()

  setInterval killOldSessions, 1000

  startTime = (new Date).getTime()

  mem = null
  updateMemory = -> mem = process.memoryUsage()

  updateMemory() 

  setInterval updateMemory, 10 * 1000 

  server.listen Number(process.env.PORT or PORT), HOST

  server.get "/", router.staticHandler "index.html"
  server.get "/style.css", router.staticHandler "style.css"
  server.get "/client.js", router.staticHandler "client.js"
  server.get "/jquery-1.2.6.min.js", router.staticHandler "jquery-1.2.6.min.js"

  server.get "/join", (req, res) ->
    nick = qs.parse(url.parse(req.url).query).nick
    if nick?.length is 0
      res.simpleJson 400, error: "Bad nick"
      return

    session = createSession nick
    if not session? 
      return res.simpleJson 400, error: "Nick in use"
      

    sys.puts "connection: #{nick}@#{res.connection.remoteAddress}"

    channel.appendMessage session.nick, "join"
    res.simpleJson 200,
      id: session.id
      nick: session.nick
      rss: mem.rss
      starttime: startTime

  server.get "/who", (req, res) ->
    nicks = []

    for id of sessions
      nicks.push sessions[id].nick

    res.simpleJson 200, { nicks: nicks, rss: mem.rss }

  server.get "/part", (req, res) ->
    id = qs.parse(url.parse(req.url).query).id
    if id && sessions[id]
      sessions[id].destroy()

    res.simpleJson 200, rss: mem.rss
    

  server.get "/recv", (req, res) ->
    since_string = qs.parse(url.parse(req.url).query).since

    unless since_string
      res.simpleJson 400, error: "Must apply since parameter!"
      return

    id = qs.parse(url.parse(req.url).query).id
    if id && sessions[id]
      session = sessions[id]
      session.poke()

    since = parseInt since_string, 10

    channel.query since, (messages) ->
      if session then session.poke()
      res.simpleJson 200,
        messages: messages
        rss: mem.rss

  server.get "/send", (req, res) ->
    id = qs.parse(url.parse(req.url).query).id

    text = qs.parse(url.parse(req.url).query).text
    unless text 
      return res.simpleJson 400, error: "No empty message allowed"

    session = sessions[id]
    unless session
      return res.simpleJson 400, error: "No session for id #{id}"

    session.poke()

    channel.appendMessage session.nick, "msg", text
    res.simpleJson 200, rss: mem.rss
  undefined
