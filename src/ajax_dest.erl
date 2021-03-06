-module(ajax_dest).
-compile(export_all).
-include("session.hrl").
-include("authkey.hrl").
-include("destination.hrl").

new(Struct, Session, _Req) ->
    [Parent, Title, Anno] = engejson:get_values(["parent", "title", "anno"], Struct),
    io:format("ajax_dest:new: ~p, ~p, ~p~n", [Parent, Title, Anno]),
    #session{opaque = #authkey{user = User = {U, D}}} = Session,
    UserCheck = list_to_binary([U, "@", D]),
    Parent1 = case Parent of
        UserCheck -> User;
        _ -> Parent
    end,
    io:format("Parent1: ~p~n", [Parent1]),
    case destination:new(User, Parent1, Title, Anno, #destprops{}) of
        {ok, Id} -> {{ok, [{"id", Id},
                           {"parent", Parent},
                           {"title", Title},
                           {"anno", Anno}]}, []};
        {error, Reason} -> {{fail, list_to_binary(Reason)}, []};
        Err -> 
            io:format("ERROR: ~p~n", [Err]),
            {{fail, <<"ERROR">>}, []}
    end.

update(Struct, Session, _Req) ->
    [Id, Title, Anno] = engejson:get_values(["id", "title", "anno"], Struct),
    #session{opaque = #authkey{user = User}} = Session,
    case destination:update(User, Id, Title, Anno, #destprops{}) of
        ok -> {{ok, [{"id", Id},
                     {"title", Title},
                     {"anno", Anno}]}, []};
        {error, Reason} -> {{fail, list_to_binary(Reason)}, []}
    end.

remove(Struct, Session, _Req) ->
    Id = engejson:get_value(<<"id">>, Struct),
    #session{opaque = #authkey{user = U}} = Session,
    destination:remove(U, Id),
    {{ok, Id}, []}.

destination(Struct, Session, _Req) ->
    Id = engejson:get_value(<<"id">>, Struct),
    #session{opaque = #authkey{user = U}} = Session,
    R = destination:destination(U, Id),
    io:format("destination: ~p~n", [R]),
    [#destination{id = {U, Id},
                  parent = {U, _ParentId},
                  uid = U,
                  title = Title,
                  anno = Anno,
                  props = #destprops{sub_allow = SubAllow,
                                     read_apvd = ReadApproved,
                                     post_apvd = PostApproved,
                                     sub_apvd = SubApproved,
                                     sub_type = SubType}}]
        = R,
    {{ok, [{"id", Id}, {"title", Title}, {"anno", Anno},
           {"sub_allow", SubAllow},
           {"read_apvd", ReadApproved},
           {"post_apvd", PostApproved},
           {"sub_apvd", SubApproved},
           {"sub_type", SubType}
          ]},
     []}.

% options: by owner, by name
destinations(_Struct, Session, _Req) ->
    #session{opaque = #authkey{user = U}} = Session,
    List = lists:map(fun(#destination{id = {Uid, Id},
                                      parent = {Uid, ParentId},
                                      uid = Uid,
                                      title = Title,
                                      anno = Anno,
                                      props = _Props}) ->
                         P = case ParentId of
                             Uid = {U1, D1} -> list_to_binary([U1, "@", D1]);
                             _ -> ParentId
                         end,
                         [{"id", Id}, {"parent", P}, {"title", Title}, {"anno", Anno}]
                     end,
                     lists:reverse(destination:destinations(U))),
    {{ok, List}, []}.
