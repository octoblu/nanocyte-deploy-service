_ = require 'lodash'
FLOW_START_NODE = 'meshblu-start'
FLOW_STOP_NODE = 'meshblu-stop'
MeshbluConfig = require 'meshblu-config'

class FlowDeployer
  constructor: (@options, dependencies={}) ->
    {@flowUuid, @instanceId, @flowToken, @forwardUrl} = @options
    {@ConfigurationSaver, @ConfigurationGenerator, MeshbluHttp} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUUid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

  deploy: (callback=->) =>
    @meshbluHttp.whoami (error, device) =>
      return callback error if error?
      @configurer = new @ConfigurationGenerator device.flow
      @configurer.configure (error, flowData) =>
        return callback error if error?
        @saver = new @ConfigurationSaver
          flowId: @flowUuid
          instanceId: @instanceId
          flowData: flowData

        @saver.save (error) =>
          return callback error if error?
          @setupDeviceForwarding device, callback

  setupDeviceForwarding: (device, callback=->) =>
    @messageHook =
      url: @forwardUrl
      method: 'POST'

    @updateMessageHooks =
      $addToSet: 'meshblu.messageHooks': @messageHook

    @meshbluHttp.updateDangerously @flowUuid, @updateMessageHooks, callback

  startFlow: (callback=->) =>
    @meshbluHttp.message [@flowUuid], payload: from: FLOW_START_NODE, callback

  stopFlow: (callback=->) =>
    @meshbluHttp.message [@flowUuid], payload: from: FLOW_STOP_NODE, callback

module.exports = FlowDeployer
