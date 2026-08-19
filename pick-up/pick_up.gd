extends Node3D

# 拖入你的预制体 ItemPrefab.tscn
@export var item_prefab: PackedScene
@export var spawn_count: int = 25  #生成多少个物体
@export var spawn_rangex: float = 4.5 #位置随机x范围
@export var spawn_rangez: float = 8.0 #位置随机z范围
@export var spawn_scalex: float = 3.0 #缩放大小x比例随机范围
@export var spawn_scalez: float = 3.0 #缩放大小x比例随机范围
@export var max_try:int = 300
#物体移动参数
@export var move_speed:float = 3
@export var dir_change_interval:float = 2.2 #多久随机换一次方向

#物体面积
@export var area:float = 1

#游戏计分
var Scores:int = 0
const GeneratedNumber = 25
const RAY_LENGTH = 1000
# @onready：场景树准备完成后自动赋值，替代手动在_ready写$查找
@onready var cam: Camera3D = $MainCamera

#保存已经放置物体的数据：中心XZ，hx，hz
var placed_list: Array[Dictionary] = []

# 模型原始未缩放半长
@export var orig_half_x:float = 1.0
@export var orig_half_z:float = 1.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	restart_game()
	# 批量生成prefab
	for i in spawn_count:
		spawn_random_item()
		
#2D AABB相交判断：true代表发生重叠
func aabb_overlap(c1:Vector2, hx1:float, hz1:float, c2:Vector2, hx2:float, hz2:float) -> bool:
	var dx = abs(c1.x - c2.x)
	var dz = abs(c1.y - c2.y)
	if dx > hx1 + hx2:
		return false
	if dz > hz1 + hz2:
		return false
	return true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta) -> void:
	pass



func _physics_process(_delta) -> void:
	for rb in get_children():
		if rb is RigidBody3D:
			var boundx = spawn_rangex
			var boundz = spawn_rangez
			var pos = rb.global_position
			var vel = rb.linear_velocity
			#边界反弹
			if pos.x > boundx or pos.x < -boundx:
				rb.linear_velocity.x = -vel.x
			if pos.z > boundz or pos.z < -boundz:
				rb.linear_velocity.z = -vel.z

func restart_game():
	Scores = 0
	pass



func _input(event):
	if event.is_action_pressed("mouse_left"):
		if event is InputEventMouseButton:
			var from = cam.project_ray_origin(event.position)
			var to = from + cam.project_ray_normal(event.position) * RAY_LENGTH;
			var query = PhysicsRayQueryParameters3D.create(from,to,2)
			var space_state = get_world_3d().direct_space_state
			var result = space_state.intersect_ray(query)
			# collider：被击中的碰撞体节点（StaticBody3D / Area3D）
			if result:
				var hit_body = result["collider"]
				var obj_name = hit_body.name   # 获取节点名字
				area = hit_body.get_meta("area") #获取物体面积
				var add_score = ConfigManager.get_score_by_area(area)
				Scores = Scores + add_score
				print("点击物体名字是",obj_name,"面积是",area,"目前分数是",Scores)
				hit_body.queue_free()


func spawn_random_item():
	var found:bool = false
	var ok_center:Vector2
	var scalex:float
	var scalez:float
	
	for attempt in max_try:
		# ========== 随机世界位置 XZ平面，Y=0地面 ==========
		var rand_x = randf_range(-spawn_rangex, spawn_rangex)
		var rand_z = randf_range(-spawn_rangez, spawn_rangez)
		var candidate = Vector2(rand_x,rand_z)
		# ========== 随机缩放比例 XZ平面，Y=0地面 ==========
		scalex = randf_range(0, spawn_scalex)
		scalez = randf_range(0, spawn_scalez)
		
		#当前候选物体的半长宽
		var cand_hx = orig_half_x * scalex
		var cand_hz = orig_half_z * scalez
		
		var overlap = false
		for placed in placed_list:
			if aabb_overlap(candidate,cand_hx,cand_hz,placed.center,placed.hx,placed.hz):
				overlap = true
				break
				
		if not overlap:
			ok_center = candidate
			found = true
			break
	
	if not found:
		print("警告：尝试次数用尽，找不到可用位置")
		return

	

	var inst:RigidBody3D = item_prefab.instantiate()
	var mesh_inst: MeshInstance3D = inst.get_node("MeshInstance3D")
	var collision_inst:CollisionShape3D = inst.get_node("CollisionShape3D")

	

	
	# ========== 修改MeshInstance3D的材质颜色 ==========
	# 获取第0号表面的原始材质
	var original_mat = mesh_inst.get_active_material(0)
	var mat: StandardMaterial3D = original_mat.duplicate()
	mat.albedo_color = Color.from_rgba8(randi_range(0,255),randi_range(0,255),randi_range(0,255))
	mesh_inst.material_override = mat

	add_child(inst)
	inst.global_position = Vector3(ok_center.x, 0.0, ok_center.y)
	mesh_inst.scale = Vector3(scalex,1,scalez)
	collision_inst.scale = Vector3(scalex,1,scalez)
	
	#存入列表
	placed_list.append({
		"center": ok_center,
		"hx": orig_half_x * scalex,
		"hz": orig_half_z * scalez
	})
	
#启动物体随机漂移逻辑
	inst.set_meta("move_speed",move_speed)
	area = area * scalex * scalez
	inst.set_meta("area",area)
	_start_object_drift(inst)

#给单个刚体启动持续随机变向 + 边界反弹
func _start_object_drift(rb:RigidBody3D):
	#定时更新移动方向
	var timer = Timer.new()
	timer.wait_time = dir_change_interval
	timer.autostart = true
	timer.timeout.connect(func():
		if not rb.is_inside_tree():
			return
		var dir = Vector3(randf_range(-1,1),0,randf_range(-1,1)).normalized()
		rb.linear_velocity = dir * rb.get_meta("move_speed")
	)
	rb.add_child(timer)
	#初始方向
	var init_dir = Vector3(randf_range(-1,1),0,randf_range(-1,1)).normalized()
	rb.linear_velocity = init_dir * move_speed
