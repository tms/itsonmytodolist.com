Prism = require 'prismjs'
Promise = require 'promise'
vm = require 'vm'
fs = require 'fs'

importLanguages = (options, logger, callback) ->
  Promise.all((options.languages or []).map((language) ->
    return new Promise((resolve, reject) ->
      path = require.resolve('prismjs/components/prism-' + language)

      logger.verbose "Attempting to register language #{ language } via #{ path }"

      fs.readFile(path, (err, code) ->
        if (err)
          reject(err)

        vm.runInNewContext(code, {
          Prism: Prism
        })

        resolve()
      )
    )
  )).then(() ->
    callback()
  ).catch((err) ->
    throw err
  )

module.exports = (env, callback) ->
  env.config.markdown = env.config.markdown or {}

  if (!env.config.markdown.highlight)
    Object.defineProperty(env.config.markdown, 'highlight', {
      writable: false,
      enumerable: true,
      value: (code, lang) ->
        grammar = Prism.languages[lang];

        if (!grammar)
          return code

        return Prism.highlight(code, grammar, lang);
    })

  importLanguages(env.config.prism or {}, env.logger, callback)