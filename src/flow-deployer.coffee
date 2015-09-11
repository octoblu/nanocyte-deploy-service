class FlowDeployer

  constructor: (flow, dependencies) ->
    @flow = flow
    @configurer = new dependencies?.ConfigurationGenerator()
    @saver = new dependencies?.ConfigurationSaver()

  deploy: (callback)=>
    @configurer.configure @flow, (error, flowData) =>
      return callback error if error
      @saver.save flowData, callback

module.exports = FlowDeployer
