_ = require 'lodash'
FLOW_START_NODE = 'meshblu-start'
FLOW_STOP_NODE = 'meshblu-stop'
MeshbluConfig = require 'meshblu-config'

class FlowDeployer
  constructor: (@options, dependencies={}) ->
    {@flowUuid, @instanceId, @flowToken, @forwardUrl, @userUuid, @userToken, @octobluUrl} = @options
    {@configurationSaver, @configurationGenerator, MeshbluHttp, @request} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    @request ?= require 'request'
    meshbluConfig = new MeshbluConfig
    meshbluJSON = _.assign meshbluConfig.toJSON(), uuid: @flowUuid, token: @flowToken
    @meshbluHttp = new MeshbluHttp meshbluJSON

  deploy: (callback=->) =>
    options =
      json: true
      auth:
        user: @userUuid
        pass: @userToken

    @request.get "#{@octobluUrl}/api/flows/#{@flowUuid}", options, (error, response, body) =>
      return callback error if error?
      @configurationGenerator.configure body, @flowToken, (error, flowData) =>
        return callback error if error?
        @configurationSaver.save
          flowId: @flowUuid
          instanceId: @instanceId
          flowData: flowData
        , (error) =>
          return callback error if error?
          @setupDeviceForwarding body, callback

  setupDeviceForwarding: (device, callback=->) =>
    @messageHook =
      url: @forwardUrl
      method: 'POST'

    @updateMessageHooks =
      $addToSet: 'meshblu.messageHooks': @messageHook

    @meshbluHttp.updateDangerously @flowUuid, @updateMessageHooks, callback

  startFlow: (callback=->) =>
    message =
      devices: [@flowUuid]
      payload:
        from: FLOW_START_NODE

    @meshbluHttp.message message, callback

  stopFlow: (callback=->) =>
    message =
      devices: [@flowUuid]
      payload:
        from: FLOW_STOP_NODE

    @meshbluHttp.message message, callback

module.exports = FlowDeployer
