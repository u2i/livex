[
  import_deps: [:phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  export: [
    locals_without_parens: [
      attribute: 2,
      has_one: 2,
      has_many: 2
    ]
  ]
]
