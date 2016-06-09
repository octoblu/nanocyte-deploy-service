_                   = require 'lodash'
async               = require 'async'
debug               = require('debug')('nanocyte-deployer:flow-deployer')
FLOW_START_NODE     = 'engine-start'
FLOW_STOP_NODE      = 'engine-stop'
MeshbluConfig       = require 'meshblu-config'
debug               = require('debug')('nanocyte-deployer:flow-deployer')
FlowStatusMessenger = require './flow-status-messenger'
SimpleBenchmark     = require 'simple-benchmark'

class FlowDeployer
  constructor: (options, dependencies={}) ->
    {@flowUuid, @instanceId, @flowToken, @forwardUrl, @userUuid, @userToken, @octobluUrl, @deploymentUuid} = options
    {@flowLoggerUuid} = options
    {@configurationSaver, @configurationGenerator, MeshbluHttp, @request} = dependencies
    @benchmark = new SimpleBenchmark label: "nanocyte-deployer-#{@flowUuid}-#{@deploymentUuid}"
    MeshbluHttp ?= require 'meshblu-http'
    @request ?= require 'request'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUuid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

    @flowStatusMessenger = new FlowStatusMessenger @meshbluHttp,
      userUuid: @userUuid
      flowUuid: @flowUuid
      workflow: 'flow-start'
      deploymentUuid: @deploymentUuid
      flowLoggerUuid: @flowLoggerUuid

  deploy: (callback=->) =>
    debug 'deploy', @benchmark.toString()
    @flowStatusMessenger.message 'begin'
    @getFlowAndUserData (error, results) =>
      debug 'getFlowAndUserData', @benchmark.toString()
      @flowStatusMessenger.message 'error', error.message if error?
      return callback error if error?

      results.flowToken = @flowToken
      results.deploymentUuid = @deploymentUuid

      @configurationGenerator.configure results, (error, config, stopConfig) =>
        debug 'configurationGenerator.configure', @benchmark.toString()
        @flowStatusMessenger.message 'error', error.message if error?
        return callback error if error?

        @clearAndSaveConfig config: config, stopConfig: stopConfig, (error) =>
          debug 'clearAndSaveConfig', @benchmark.toString()
          @flowStatusMessenger.message 'error', error.message if error?
          return callback error if error?

          @setupDevice results.flowData, config, (error) =>
            debug 'setupDevice', @benchmark.toString()
            @flowStatusMessenger.message 'error', error.message if error?
            @flowStatusMessenger.message 'end' unless error?
            callback error

  destroy: (callback=->) =>
    @configurationSaver.stop flowId: @flowUuid, (error) =>
      debug 'configurationSaver.stop', @benchmark.toString()
      callback error

  clearAndSaveConfig: (options, callback) =>
    {config, stopConfig} = options

    saveOptions =
      flowId: @flowUuid
      instanceId: @instanceId
      flowData: config

    saveStopOptions =
      flowId: "#{@flowUuid}-stop"
      instanceId: @instanceId
      flowData: stopConfig

    async.series [
      async.apply @configurationSaver.stop, flowId: @flowUuid
      async.apply @configurationSaver.save, saveOptions
      async.apply @configurationSaver.save, saveStopOptions
    ], callback

  getFlowAndUserData: (callback) =>
    async.parallel
      userData: async.apply @_get, "#{@octobluUrl}/api/user"
      flowData: async.apply @_get, "#{@octobluUrl}/api/flows/#{@flowUuid}"
    , callback

  _get: (url, callback)=>
    options =
      json: true
      auth:
        user: @userUuid
        pass: @userToken

    @request.get url, options, (error, response, body) =>
      callback error, body

  setupDevice: (flow, flowConfig, callback=->) =>
    async.series [
      async.apply @createSelfSubscriptions
      async.apply @createSubscriptions, flowConfig
      async.apply @setupDeviceForwarding
      async.apply @setupMessageSchema, flow.nodes
      async.apply @addFlowToDevice, flow
    ], callback

  addFlowToDevice:(flow, callback) =>
    @meshbluHttp.updateDangerously @flowUuid, $set: flow: flow, callback

  setupDeviceForwarding: (callback=->) =>
    messageHook =
      url: @forwardUrl
      method: 'POST'
      signRequest: true
      name: 'nanocyte-flow-deploy'
      type: 'webhook'

    query =
      uuid: @meshbluHttp.uuid

    projection =
      uuid: true
      'meshblu.forwarders.broadcast': true

    @meshbluHttp.search query, {projection}, (error, devices) =>
      return callback error if error?
      device = _.first devices

      pullMessageHooks =
        $pull:
          'meshblu.forwarders.received': {name: messageHook.name}
          'meshblu.messageHooks': {name: messageHook.name}
          'meshblu.forwarders.broadcast.received': {name: messageHook.name}
          'meshblu.forwarders.message.received': {name: messageHook.name}

      addNewMessageHooks =
        $addToSet:
          'meshblu.forwarders.broadcast.received': messageHook
          'meshblu.forwarders.message.received': messageHook

      tasks = [
        async.apply @meshbluHttp.updateDangerously, @flowUuid, pullMessageHooks
        async.apply @meshbluHttp.updateDangerously, @flowUuid, addNewMessageHooks
      ]

      if _.isArray device?.meshblu?.forwarders?.broadcast
        removeOldMessageHooks =
          $unset:
            'meshblu.forwarders.broadcast': ''

        tasks.unshift async.apply @meshbluHttp.updateDangerously, @flowUuid, removeOldMessageHooks

      async.series tasks, (error) =>
        debug 'setupDeviceForwarding', @benchmark.toString()
        callback error

  setupMessageSchema: (nodes, callback=->) =>
    triggers = _.filter nodes, class: 'trigger'

    messageSchema =
      type: 'object'
      properties:
        from:
          type: 'string'
          title: 'Trigger'
          required: true
          enum: _.pluck(triggers, 'id')
        payload:
          title: "payload"
          description: "Use {{msg}} to send the entire message"
        replacePayload:
          type: 'string'
          default: 'payload'

    messageFormSchema = [
      { key: 'from', titleMap: @buildFormTitleMap triggers }
      { key: 'payload', 'type': 'input', title: "Payload", description: "Use {{msg}} to send the entire message"}
    ]
    setMessageSchema =
      $set : { 'messageSchema': messageSchema, 'messageFormSchema': messageFormSchema }

    @meshbluHttp.updateDangerously @flowUuid, setMessageSchema, (error) =>
      debug 'setupMessageSchema', @benchmark.toString()
      callback error

  buildFormTitleMap: (triggers) =>
    _.transform triggers, (result, trigger) ->
      triggerId = _.first trigger.id.split /-/
      result[trigger.id] = "#{trigger.name} (#{triggerId})"
    , {}

  createSelfSubscriptions: (callback) =>
    subscriptions =
      'broadcast.received': [@flowUuid]
      'message.received': [@flowUuid]

    async.forEachOf subscriptions, @createSubscriptionsForType, callback

  createSubscriptions: (flowConfig, callback) =>
    async.forEachOf flowConfig['subscribe-devices'].config, @createSubscriptionsForType, (error) =>
      debug 'createSubscriptions', @benchmark.toString()
      callback error

  createSubscriptionsForType: (uuids, type, callback) =>
    debug 'createSubscriptions', {uuids, type}
    async.each uuids, ((uuid, cb) => @createSubscriptionForType uuid, type, cb), callback

  createSubscriptionForType: (emitterUuid, type, callback) =>
    subscriberUuid = @flowUuid
    debug '@meshbluHttp.createSubscription', {subscriberUuid, emitterUuid, type}
    @meshbluHttp.createSubscription {subscriberUuid, emitterUuid, type}, callback

  startFlow: (callback=->) =>
    onStartMessage =
      devices: [@flowUuid]
      payload:
        from: FLOW_START_NODE

    subscribePulseMessage =
      devices: [@flowUuid]
      topic: 'subscribe:pulse'

    _.defer @flowStatusMessenger.message, 'begin', undefined, application: 'flow-runner'
    async.parallel [
      async.apply @meshbluHttp.message, subscribePulseMessage
      async.apply @meshbluHttp.message, onStartMessage
      async.apply @meshbluHttp.updateDangerously, @flowUuid, $set: {online: true, deploying: false, stopping: false}
    ], callback

  stopFlow: (callback=->) =>
    async.parallel [
      async.apply @sendStopFlowMessage
      async.apply @meshbluHttp.updateDangerously, @flowUuid, $set: {online: false, deploying: false, stopping: false}
    ], callback

  sendStopFlowMessage: (callback) =>
    message =
      devices: [@flowUuid]
      payload:
        from: FLOW_STOP_NODE

    @meshbluHttp.message message, callback

module.exports = FlowDeployer
