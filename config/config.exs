import Config

if Mix.env() == :dev do
  esbuild = fn args ->
    [
      args: ~w(./js/livex --bundle) ++ args,
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]
  end

  lv_vsn = Mix.Project.config()[:version]

  config :esbuild,
    version: "0.20.2",
    module:
      esbuild.(
        ~w(--format=esm --sourcemap --define:LV_VSN="#{lv_vsn}" --outfile=../priv/static/livex.esm.js)
      ),
    main:
      esbuild.(
        ~w(--format=cjs --sourcemap --define:LV_VSN="#{lv_vsn}" --outfile=../priv/static/livex.cjs.js)
      ),
    cdn:
      esbuild.(
        ~w(--format=iife --target=es2016 --global-name=LiveView --define:LV_VSN="#{lv_vsn}" --outfile=../priv/static/livex.js)
      ),
    cdn_min:
      esbuild.(
        ~w(--format=iife --target=es2016 --global-name=LiveView --minify --define:LV_VSN="#{lv_vsn}" --outfile=../priv/static/livex.min.js)
      )
end

import_config "#{config_env()}.exs"
