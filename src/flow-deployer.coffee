_ = require 'lodash'
FLOW_START_NODE = 'meshblu-start'
FLOW_STOP_NODE = 'meshblu-stop'
class FlowDeployer
  constructor: (@flowUuid, @flowToken, @forwardUrl, dependencies={}) ->
    {@ConfigurationSaver, @ConfigurationGenerator, MeshbluHttp} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    @meshbluHttp = new MeshbluHttp @flowUUid, @flowToken

  deploy: (callback=->) =>
    @meshbluHttp.whoami (error, device) =>
      return callback error if error?
      @configurer = new @ConfigurationGenerator device.flow
      @configurer.configure (error, flowData) =>
        return callback error if error?
        @saver = new @ConfigurationSaver flowData
        @saver.save (error) =>
          return callback error if error?
          @setupDeviceForwarding device, callback

  setupDeviceForwarding: (device, callback=->) =>
    @messageHook = url: @forwardUrl, method: 'POST'

    @createMessageHooks =
      $set: 'meshblu.messageHooks': [ @messageHook ]

    @updateMessageHooks =
      $push: 'meshblu.messageHooks': @messageHook

    return callback null if _.findWhere(device.meshblu?.messageHooks, @messageHook)?
    return @meshbluHttp.updateDangerously @flowUuid, @createMessageHooks, callback unless device.meshblu?.messageHooks

    @meshbluHttp.updateDangerously @flowUuid, @updateMessageHooks, callback

  startFlow: (callback=->) =>
    @meshbluHttp.message [@flowUuid], payload: from: FLOW_START_NODE, callback

  stopFlow: (callback=->) =>
    @meshbluHttp.message [@flowUuid], payload: from: FLOW_STOP_NODE, callback

module.exports = FlowDeployer
