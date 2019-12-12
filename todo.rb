require 'sinatra'
require 'sinatra/content_for'
require 'tilt/erubis'

require_relative 'database_persistence'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'database_persistence.rb' 
end

before do
  @storage = DatabasePersistence.new(logger)
end

before "/lists/:list_id*" do
  return if params[:list_id] == 'new'
  @list_id = params[:list_id].to_i
  @list    = load_list(@list_id)
  @todos   = @list[:todos]
end

before "/lists/:list_id/todos/:todo_id*" do
  @list_id = params[:list_id].to_i
  @list    = load_list(@list_id)
  @todos   = @list[:todos]
  @todo_id = params[:todo_id].to_i
  @todo    = @todos[@todo_id]
end

after do
  @storage.disconnect
end

helpers do
  def list_complete?(list)
    list[:todos_count] > 0 && list[:todos_remaining_count].zero?
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition { |list| list_complete?(list) }

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos, &block)
    complete_todos, incomplete_todos = todos.partition { |todo| todo[:completed] }

    incomplete_todos.each(&block)
    complete_todos.each(&block)
  end
end

def load_list(id)
  list = @storage.find_list(id)
  return list if list

  session[:error] = "The specified list was not found"
  redirect "/lists"
end

get "/" do
  redirect "/lists"
end

# View list of lists
get "/lists" do
  @lists = @storage.all_lists
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "List name must be between 1 and 100 characters."
  elsif @storage.all_lists.any? { |list| list[:name] == name }
    "List name must be unique."
  end
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip
  error = error_for_list_name(list_name)

  if error
    session[:error] = error
    erb :new_list
  else
    @storage.create_new_list(list_name)
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

get "/lists/:id" do
  erb :list
end

# Edit an existing todo list
get "/lists/:id/edit" do
  erb :edit_list
end

# Update an existing todo list
post "/lists/:id" do
  list_name = params[:list_name].strip
  error = error_for_list_name(list_name)

  if error
    session[:error] = error
    erb :edit_list
  else
    @storage.update_list_name(@list_id, list_name)
    session[:success] = "The list has been updated."
    redirect "/lists/#{@list_id}"
  end
end

# Delete an existing todo list
post "/lists/:id/destroy" do
  @storage.delete_list(@list_id)

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    session[:success] = "The list has been deleted."
    redirect "/lists"
  end
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  text = params[:todo].strip
  error = error_for_todo(text)

  if error
    session[:error] = error
    erb :list
  else
    @storage.create_new_todo(@list_id, text)
    session[:success] = "The to-do was added."
    redirect "/lists/#{@list_id}"
  end
end

# Return an error message if the todo is invalid. Return nil if name is valid.
def error_for_todo(name)
  if !(1..100).cover? name.size
    "To-do must be between 1 and 100 characters."
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:id/destroy" do
  @storage.delete_todo_from_list(@list_id, @todo_id)

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204      # no content
  else
    session[:success] = "The to-do has been deleted."
    redirect "/lists/#{@list_id}"
  end
end

# Update the status of a todo
post "/lists/:list_id/todos/:id" do
  is_completed = params[:completed] == "true"
  @storage.update_todo_status(@list_id, @todo_id, is_completed)

  session[:success] = "The to-do has been updated."
  redirect "/lists/#{@list_id}"
end

# Mark all todos as complete for a list
post "/lists/:id/complete_all" do
  @storage.mark_all_todos_as_completed(@list_id)
  session[:success] = "All the to-dos have been completed."
  redirect "/lists/#{@list_id}"
end