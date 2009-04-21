%% @author Dmitry Chernyak <losthost@narod.ru>
%% @copyright Copyleft 2009 

%% @doc Entry storage
%%
%% Uses CouchDB
%%

-module(entry).
-export([create/3, update/5, create_view/2, create_view/3, read/2, delete/3, get_attach/3, put_attach/6, reset/0, reset_view/0]).

-define(DB, "entries").

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

uid_to_json({U, D}) -> [{uid, U}, {domain, D}].

date_json() ->
    {{Y, M, D}, {HH, MM, SS}} = erlang:localtime(),
    [{year, Y}, {month, M}, {day, D},
     {hour, HH}, {minute, MM}, {second, SS}].


%% @spec create(uid(), destination(), [field()]) -> {ok, id(), rev()} | {error, reason()}
%% @doc Create new document. Date and Id is autogenerated internally

%% field() = [{name, binary()}, {values, [value()]}]

%% value() = [{name, binary()}, {type, binary()}, {value, json()}]
create(Uid, Destination, Fields) ->
    Guid = list_to_binary(session:guid()),
    Obj = [{'_id', Guid},
           {type, entry},
           {author, uid_to_json(Uid)},
           {date, date_json()},
           {destination, Destination},
           {fields, Fields}],
    Result = ecouch:doc_create(?DB, Guid, Obj),
    io:format("save result: ~p~n", [Result]),
    decode_result(Result).

%% @spec update(uid(), id(), rev(), destination(), [field()]) -> {ok, id(), rev()} | {error, reason()}
%% @doc Update document. Date and Id is autogenerated internally
update(Uid, Id, Rev, Destination, Fields) ->
    Obj = [{'_id', Id},
           {'_rev', Rev},
           {type, entry},
           {author, uid_to_json(Uid)},
           {date, date_json()},
           {destination, Destination},
           {fields, Fields}],
    Result = ecouch:doc_update(?DB, Id, Obj),
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

%% @spec read(uid(), id()) -> {ok, doc()} | {error, reason()}
read(Uid, Id) ->
    ecouch:doc_get(?DB, Id).

%% @spec delete(uid(), id(), rev()) -> {ok, doc()} | {error, reason()}
delete(Uid, Id, Rev) ->
    ecouch:doc_delete(?DB, Id, Rev).

%% @spec get_attach(uid(), id(), name()) -> {bin, binary()} | {error, reason()}
get_attach(Uid, Id, Name) ->
    ecouch:attach_get(?DB, list_to_binary([Id, "/", Name])).

%% @spec put_attach(uid(), id(), rev(), name(), contenttype(), data()) -> {ok, json()} | {error, reason()}
put_attach(Uid, Id, Rev, Name, ContentType, Data) ->
    Result = ecouch:attach_put(?DB, list_to_binary([Id, "/", Name]), Rev, ContentType, Data),
    decode_result(Result).

reset() ->
    ecouch:db_delete(?DB),
    ecouch:db_create(?DB),
    reset_view(),
    reset_template().

reset_template() ->
    {ok, Data} = file:read_file("conf/entries.json"),
    lists:map(fun(X) -> create({<<"system">>, <<"localhost">>}, <<"system">>, X) end,
              engejson:decode(Data)).

reset_view() ->
    Id = "_design/store",
    case ecouch:doc_get(?DB, Id) of
        {ok, Json} ->
            Rev = engejson:get_value(<<"_rev">>, Json),
            ecouch:doc_delete(?DB, Id, Rev);
        _ -> ok
    end,
    case create_view("store", [{"entries", "
function(doc){
    var test = function(X){return X};
    var extract_field = function(doc, fld){
        return doc.fields.map(function(field){
            if(field.name == fld)
                return field.values.map(function(value){
                    if(value.name == fld) return value.value
                    else return undefined
                }).filter(test)
            else return undefined
        }).filter(test)[0]
    };
    if(doc.type == 'entry')
        emit(doc.author, {'rev': doc._rev, 'date': doc.date, 'destination': doc.destination,
                          'title': extract_field(doc, 'Название'), 'type': extract_field(doc, 'Тип')})
}", null},
                               {"owner","
function(doc){ if(doc.type == 'entry') emit({'author': doc.author, 'id': doc._id}, null) }
", null},
                               {"template","
function(doc){
    var test = function(X){return X};
    var extract_field = function(doc, fld, val){
        return doc.fields.map(function(field){
            if(field.name == fld)
                return field.values.map(function(value){
                    if((value.name == fld) && ((val == undefined) || (value.value == val)))
                        return value.value
                    else
                        return undefined
                }).filter(test)
            else return undefined
        }).filter(test)[0]
    };
    if(doc.type == 'entry')
        if(extract_field(doc, 'Тип', 'Шаблон').length > 0)
            emit(extract_field(doc, 'Название')[0], {'type': extract_field(doc, 'Тип')[0]})
}", null},
                               {"value","
function(doc){
    var test = function(X){return X};
    var extract_field = function(doc, fld, val){
        return doc.fields.map(function(field){
            if(field.name == fld)
                return field.values.map(function(value){
                    if((value.name == fld) && ((val == undefined) || (value.value == val)))
                        return value.value
                    else
                        return undefined
                }).filter(test)
            else return undefined
        }).filter(test)[0]
    };
    if(doc.type == 'entry')
        if(extract_field(doc, 'Тип', 'Значение').length > 0){
            var name = extract_field(doc, 'Название')[0];
            emit(name, {'name': name, 'type': extract_field(doc, 'Данные')[0]})
        }
}", null}
                              ])
    of
        {ok, _Id, _Rev} -> ok;
        {error, Reason} ->
            io:format("create view fail: ~p~n", [Reason]),
            {error, Reason}
    end.
