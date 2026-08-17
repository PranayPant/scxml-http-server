To automatically generate TypeScript interfaces from your Elixir structs, you have two primary approaches: use a lightweight code-generation library designed specifically for this task, or leverage your API contract layer (which is usually the safest and most scalable production method). [1] 
## Option 1: Use Dedicated Type-Gen Libraries
If you want to maintain plain Elixir structs and parse their types directly into .ts files, you can use specialized Elixir hex packages.

* 
* type_translator / ex_ts: Libraries like type_translator analyze modules with @type t() definitions and compile them down to matching TypeScript types.
* [genus](https://github.com/bwireman/genus): An Elixir macro-based library designed specifically to synchronize Elixir structs and TypeScript definitions. You define the fields using its DSL, and it handles creating both the Elixir struct layout and generating the associated TypeScript types. [2, 3, 4, 5] 
* 

Example using standard Elixir AST parsing (Custom Mix Task):
If you want complete control without adding too many dependencies, you can create a custom mix task that reflects on your modules at compile time:

# lib/mix/tasks/gen_ts.ex
defmodule Mix.Tasks.Gen.Ts do
  use Mix.Task

  def run(_) do
    # Fetch the public typespecs of a module
    {:ok, types} = Code.Typespec.fetch_types(YourApp.User)
    
    # Parse the AST and map Elixir primitives to TypeScript
    ts_interface = translate_to_ts("User", types)
    
    File.write!("../frontend/types/generated.ts", ts_interface)
  end
  
  defp translate_to_ts(name, types) do
    # Logic to map :string -> string, :integer -> number, etc.
  end
end

------------------------------
## Option 2: Rely on Your API Contract Layer (Recommended)
In most production setups, generating types directly from database or internal structs leaks backend implementation details to the frontend. It is usually better to generate TypeScript interfaces based on what your API actually exposes.
## 1. JSON REST APIs: OpenApiSpex
If you use Phoenix for a REST API, you can use [OpenApiSpex](https://github.com/open-api-spex/open_api_spex). It allows you to write schemas in Elixir that double as runtime validation and documentation.

   1. Define your struct's OpenApi schema in Elixir:
   
   defmodule YourApp.UserSchema do
     OpenApiSpex.schema(%{
       title: "User",
       type: :object,
       properties: %{
         id: %{type: :integer},
         name: %{type: :string},
         email: %{type: :string, format: :email}
       }
     })
   end
   
   2. Run the built-in Mix task to output an openapi.json file.
   3. In your frontend repository, use the popular npm package openapi-typescript:
   
   npx openapi-typescript openapi.json --output ./types/api.ts
   
   
## 2. GraphQL APIs: Absinthe + GraphQL Code Generator [6] 
If your frontend communicates via GraphQL using [Absinthe](https://github.com/absinthe-graphql/absinthe), the schema is already strongly typed. [6] 

   1. Dump your Absinthe schema to a schema file using the command:
   
   mix absinthe.schema.json
   
   2. On your frontend, use GraphQL Code Generator. It will read the JSON schema and generate perfectly typed TypeScript hooks, interfaces, and operations automatically. [6, 7] 

## 3. Full-Stack Data Layers: Ash Framework
If you are using the Ash Framework, you can use [ash_typescript](https://github.com/ash-project/ash_typescript). Running mix ash_typescript.codegen completely automates the process by reading your Ash resources and rendering fully-typed frontend client interfaces without any manual mapping. [8, 9, 10] 
------------------------------
Which architectural style are you using for this project—a standard Phoenix REST API, GraphQL via Absinthe, or are you looking to output raw text files straight from your internal utility modules?

[1] [https://www.youtube.com](https://www.youtube.com/watch?v=cJyl9e2oqHY)
[2] [https://github.com](https://github.com/bwireman/genus)
[3] [https://github.com](https://github.com/bwireman/genus)
[4] [https://zachporter.dev](https://zachporter.dev/posts/lets-code-contact-form-in-phoenix-part-one/)
[5] [https://kieran.casa](https://kieran.casa/io-ts/)
[6] [https://elixirforum.com](https://elixirforum.com/t/how-to-define-frontend-backend-contract-with-elixir-typescript/40466)
[7] [https://www.easecloud.io](https://www.easecloud.io/tools/code-generators/typescript-interface-generator/)
[8] [https://hexdocs.pm](https://hexdocs.pm/ash_typescript/mix-tasks.html)
[9] [https://github.com](https://github.com/ash-project/ash_typescript)
[10] [https://hexdocs.pm](https://hexdocs.pm/ash_typescript/)
