_ = require 'lodash'

class FlowDeployer
  constructor: (@flowUuid, @flowToken, @forwardUrl, dependencies={}) ->
    {ConfigurationSaver, ConfigurationGenerator, MeshbluHttp} = dependencies
    MeshbluHttp ?= require 'meshblu-http'
    @configurer = new ConfigurationGenerator
    @saver = new ConfigurationSaver
    @meshbluHttp = new MeshbluHttp @flowUUid, @flowToken

  deploy: (callback) =>
    @meshbluHttp.whoami (error, device) =>
      return callback error if error?
      @configurer.configure device.flow, (error, flowData) =>
        return callback error if error
        @saver.save flowData, callback

  setupDeviceForwarding: (device, callback) =>
    @messageHook = url: @forwardUrl, method: 'POST'
    @createMessageHooks =
      $set: 'meshblu.messageHooks': [ @messageHook ]
    @updateMessageHooks =
      $push: 'meshblu.messageHooks': @messageHook

    return callback null if _.findWhere(device.meshblu?.messageHooks, @messageHook)?
    return @meshbluHttp.updateDangerously @flowUuid, @createMessageHooks, callback unless device.meshblu?.messageHooks

    @meshbluHttp.updateDangerously @flowUuid, @updateMessageHooks, callback


  startFlow: =>

  stopFlow: =>

module.exports = FlowDeployer
