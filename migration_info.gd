extends Node
class_name MigrationInfo

var host_migration_order := [] # queue of GotmUser in the order of who hosts next
var migration_room_code := ""
var network_peers := {} # dict of all players as network_id: GotmUser

var _did_host_leave: bool = false # flag for knowing when to do migration


func add_player(network_id: int, user: GotmUser) -> void:
	network_peers[network_id] = user
	host_migration_order.append(user)


func remove_player(network_id: int) -> void:
	if network_peers.has(network_id):
		var player: GotmUser = network_peers[network_id]
		host_migration_order.erase(player)
	network_peers.erase(network_id)
