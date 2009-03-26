%% @author Dmitry Chernyak <losthost@narod.ru>
%% @copyright Copyleft 2009 

%% @doc Writings storage
%%
%% Uses CouchDB
%%

-module(writing).
-export([create_doc/4, create_view/2, create_view/3, read/1, delete/2, get_attach/2, put_attach/5, reset/0]).

-define(DB, "writings").

%% @spec decode_result(result()) -> {ok, id(), rev()} | {error, reason()}
%% @doc Decode ecouch function result
decode_result({ok, Result}) ->
    case engejson:get_values(["ok", "id", "rev"], Result) of
        [true, Id, Rev] ->
            io:format("doc id=~p, rev=~p~n",[Id, Rev]),
            {ok, Id, Rev};
        _NoOk -> {error, Result}
    end;

decode_result(Error) -> Error.
    
%% @spec create_doc(uid(), destination(), title(), props()) -> {ok, id(), rev()} | {error, reason()}
%% @doc Create new document. Id is autogenerated internally.
create_doc(Uid, Destination, Title, Props) ->
    %[{"ok",true},
    % {"id",<<"8d80981151b8cecd024b804c0c51c97b">>},
    % {"rev",<<"101943079">>}]
    Guid = session:guid(),
    Obj = [{'_id', Guid},
           {author, Uid},
           {date, now()},
           {destination, Destination},
           {title, Title},
           {props, Props}],
    {ok, Result} = ecouch:doc_create(?DB, Guid, Obj),
    io:format("save doc: ~p~n", [Result]),
    decode_result(Result).

compose_mapreduce(Name, Map, Reduce) ->
    {Name, case Reduce of
               null ->  [{map, list_to_binary(Map)}];
               _ -> [{map, list_to_binary(Map)}, {reduce, list_to_binary(Reduce)}]
           end}.

compose_views(MRList) ->
    compose_views(MRList, []).

compose_views([], Acc) ->
    lists:reverse(Acc);
    
compose_views([{Name, Map, Reduce} | T], Acc) ->
    compose_views(T, [compose_mapreduce(Name, Map, Reduce) | Acc]).

%% @spec create_view(design(), mrlist()) -> {ok, id(), rev()} | {error, reason()}
%% @doc Create javascript view document
%% @type mrlist() = {name(), map(), reduce()}
%% @type map() = javascript()
%% @type reduce() = javascript()
create_view(Design, MRList) ->
    create_view(Design, javascript, MRList).

%% @spec create_view(design(), language(), mrlist()) -> {ok, id(), rev()} | {error, reason()}
%% @doc Create view document
%% @type language() = atom() | binary(). Language name, possible 'javascript'.
%% @type mrlist() = [{name(), map(), reduce()}]
%% @type map() = javascript()
%% @type reduce() = javascript()
create_view(Design, Language, MRList) ->
    ViewName = "_design/" ++ Design,
    Views = compose_views(MRList),
    Obj = [{'_id', list_to_binary(ViewName)},
           {language, Language},
           {views, Views}],
    io:format("create view: ~p~n", [Obj]),
    Result = ecouch:doc_create(?DB, ViewName, Obj),
    decode_result(Result).

%% @spec read(id()) -> {ok, doc()} | {error, reason()}
read(Id) ->
    ecouch:doc_get(?DB, Id).

%% @spec delete(id(), rev()) -> {ok, doc()} | {error, reason()}
delete(Id, Rev) ->
    ecouch:doc_delete(?DB, Id, Rev).

%% @spec get_attach(id(), name()) -> {bin, binary()} | {error, reason()}
get_attach(Id, Name) ->
    ecouch:attach_get(?DB, list_to_binary([Id, "/", Name])).

%% @spec put_attach(id(), rev(), name(), contenttype(), data()) -> {ok, json()} | {error, reason()}
put_attach(Id, Rev, Name, ContentType, Data) ->
    Result = ecouch:attach_put(?DB, list_to_binary([Id, "/", Name]), Rev, ContentType, Data),
    decode_result(Result).

reset() ->
    ecouch:db_delete(?DB),
    ecouch:db_create(?DB),
    case create_view("listing", "writings", [{"all", "function(doc){ if(doc.type == 'writing') emit(doc.author, doc) }", null}])
    of
        {ok, _Id, _Rev} -> ok;
        {error, _Reason} -> error
    end.
