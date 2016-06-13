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
    {
      @flowUuid
      @instanceId
      @flowToken
      @forwardUrl
      @userUuid
      @userToken
      @octobluUrl
      @deploymentUuid
      @flowLoggerUuid
      @client
    } = options
    {
      @configurationSaver
      @configurationGenerator
      MeshbluHttp
    } = dependencies

    @benchmark = new SimpleBenchmark label: "nanocyte-deployer-#{@flowUuid}-#{@deploymentUuid}"
    MeshbluHttp ?= require 'meshblu-http'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUuid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

    throw new Error 'NanocyteDeployer requires client' unless @client?

    @flowStatusMessenger = new FlowStatusMessenger @meshbluHttp,
      userUuid: @userUuid
      flowUuid: @flowUuid
      workflow: 'flow-start'
      deploymentUuid: @deploymentUuid
      flowLoggerUuid: @flowLoggerUuid

  deploy: (callback=->) =>
    debug 'deploy', @benchmark.toString()
    @flowStatusMessenger.message 'begin'
    @getFlowDevice (error) =>
      return @_handleError error, callback if error?
      flowData = @flowDevice.flow
      @configurationGenerator.configure {flowData, @flowToken, @deploymentUuid}, (error, config, stopConfig) =>
        debug 'configurationGenerator.configure', @benchmark.toString()
        return @_handleError error, callback if error?

        @clearAndSaveConfig {config, stopConfig}, (error) =>
          debug 'clearAndSaveConfig', @benchmark.toString()
          return @_handleError error, callback if error?

          @setupDevice {flowData, config}, (error) =>
            debug 'setupDevice', @benchmark.toString()
            return @_handleError error, callback if error?
            @flowStatusMessenger.message 'end'
            callback()

  destroy: (callback=->) =>
    @_stop {flowId: @flowUuid}, callback

  _stop: ({flowId}, callback) =>
    @configurationSaver.stop {flowId}, (error) =>
      debug 'configurationSaver.stop', @benchmark.toString()
      return callback error if error?
      @client.del flowId, callback

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
      async.apply @_stop, flowId: @flowUuid
      async.apply @configurationSaver.save, saveOptions
      async.apply @configurationSaver.save, saveStopOptions
    ], callback

  getFlowDevice: (callback) =>
    return callback() if @flowDevice?

    query =
      uuid: @flowUuid

    projection =
      uuid: true
      flow: true
      'meshblu.forwarders.broadcast': true

    @meshbluHttp.search query, {projection}, (error, devices) =>
      return callback error if error?
      @flowDevice = _.first devices
      unless @flowDevice?
        error = new Error 'Device Not Found'
        error.code = 404
        return callback error
      unless @flowDevice?.flow
        error = new Error 'Device is missing flow property'
        error.code = 400
        return callback error
      callback null, @flowDevice

  setupDevice: ({flowData, config}, callback=->) =>
    async.series [
      async.apply @createSelfSubscriptions
      async.apply @createSubscriptions, config
      async.apply @setupDeviceForwarding
      async.apply @setupMessageSchema, flowData.nodes
    ], callback

  setupDeviceForwarding: (callback=->) =>
    messageHook =
      url: @forwardUrl
      method: 'POST'
      signRequest: true
      name: 'nanocyte-flow-deploy'
      type: 'webhook'

    @getFlowDevice (error) =>
      return callback error if error?

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

      if _.isArray @flowDevice?.meshblu?.forwarders?.broadcast
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

  _handleError: (error, callback) =>
    @flowStatusMessenger.message 'error', error.message
    callback error

module.exports = FlowDeployer
