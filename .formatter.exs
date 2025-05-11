[
  import_deps: [:phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  export: [
    locals_without_parens: [
      prop: 2,
      prop: 3,
      state: 2,
      state: 3
    ]
  ]
]
