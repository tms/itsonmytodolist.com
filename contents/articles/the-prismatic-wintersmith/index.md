---
title: The Prismatic Wintersmith
date: 2015-04-13 00:25
template: article.jade
---

I'm a parent now, which means that eventually the temper tantrums and
children's shows will eat away at my sanity. As someone who is responsible for
finding implementations and fixing bugs that don't have an easily Google-able
solution, it seemed useful to put together a blog to store that information
somewhere safer than my head.

---

That and the fact that [Nick Craver][1] recently redid his blog, which I've
decided to co-opt as an excuse to stop being lazy and actually make use of
this domain. While he took advantage of GitHub's great Jekyll-backed
[Pages feature][2] in his redesign, as a Windows user I was [a little wary][3]
of going this route:

> While Windows is not an officially-supported platform, it can be used to run
> Jekyll <span class="highlight">with the proper tweaks</span>

Though this isn't the most ominous compatibility warning I've ever read, it was
enough to convince me that it'd be quicker to start with a static site generator
that ran on something I already had installed, like Node. Searching around for
Node-powered options turned up several viable results, but in the end I settled
on [Wintersmith][4].

A keen observer might have noted that development on Wintersmith by the original
author seems to have stalled in the last year or so, which could be problematic.
Given the small footprint of the codebase though, I'm not overly concerned with
being able to work around any problems I run into&mdash;barring that, I can
always fork!

As it turns out, the use of [highlight.js][5] for syntax highlighting by the
built-in Markdown plugin gave me the chance to put the first option to the test.
Highlight.js is a well-equipped highlighting library, but it intentionally
doesn't tokenize punctuation and that's something I was interested in for
styling. Other options like [Prettify][6] and [Prism.js][7] thankfully do, and
while I'm familiar with Prettify from meddling in bug reports on Stack Exchange,
I decided to give Prism a go in the interest of trying something new.

It looks like Prism [might still not be published on npm][8], but the level of
node support I needed is there, so adding it as a dependency was no issue:

```
npm install git+https://github.com/LeaVerou/prism.git#gh-pages --save
```

Note that due to the way development happens on the repo, pulling from the
`gh-pages` branch was the "better" choice.

With Prism available locally, the next step was to change the
[`highlight` option][9] that Wintersmith's Markdown plugin passes to
[marked][10], the included Markdown converter. Unfortunately there's no good way
to do this with the existing code, so I decided to hack it into submission with
a custom plugin.

Wintersmith makes this process easy enough by allowing you to create a node
module that will be invoked on startup via a config option:

```javascript
"plugins": [
  "./plugins/prismjs.coffee"
]
```

Plugins can call the [registration hooks][11] as necessary, but as I only needed
to subvert the assignment of `highlight` without having to essentially replace
the existing plugin, I created a simple module that abuses JavaScript's
read-only properties to force my `highlight` definition to pass through
untouched: 

```coffeescript
module.exports = (env, callback) ->
  env.config.markdown = env.config.markdown or {}

  if (!env.config.markdown.highlight)
    Object.defineProperty(env.config.markdown, 'highlight', {
      writable: false,
      enumerable: true,
      value: (code, lang) ->
        code
    })

  callback()
```
 
No error is thrown when an assignment is made to a read-only property, the value
just doesn't change. I did check that the property wasn't already set though,
as trying to redefine an existing property *will* throw one.

With control over`highlight` established, adding in the Prism bits was easy
enough:

```coffescript
Prism = require 'prismjs'

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

  callback()
```

&hellip;or it would have been easy if requiring Prism brought in all languages,
but since the module is really just a bundled file for use on the Prism site it
only includes the ones that make sense in that context.

Not willing to switch to something else at that point in the game, I extended
the plugin to pull in additional languages as specified by a configuration
option:

```javascript
"prism": {
  "languages": ["java", "coffeescript", "csharp", "r", "sql", "bash"]
}
```

Since the language files aren't written with node support in mind, getting them
registered involved reading their contents and executing them with node's
[`vm` module][12], using a context object to make `Prism` available in their
local scope. Reading the files is done asynchronously, so I sprinkled in a
little [promise magic][13] for good measure:

```coffeescript
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
``` 

And that did it. Running `wintersmith build` produced the site you see now,
complete with [Prism][7] highlighting.

  [1]: http://nickcraver.com 
  [2]: https://pages.github.com/
  [3]: http://jekyllrb.com/docs/windows/
  [4]: http://wintersmith.io/
  [5]: https://highlightjs.org/
  [6]: https://code.google.com/p/google-code-prettify/
  [7]: http://prismjs.com/
  [8]: https://github.com/PrismJS/prism/pull/179
  [9]: https://github.com/jnordberg/wintersmith/blob/718250eefdef08e9667650c350da0fb37c185936/src/plugins/markdown.coffee#L51
  [10]: https://github.com/chjj/marked
  [11]: https://github.com/jnordberg/wintersmith/wiki/Writing-plugins
  [12]: https://nodejs.org/api/vm.html
  [13]: https://github.com/then/promise