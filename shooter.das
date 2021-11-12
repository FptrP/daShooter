require daslib/media

let
    SCREEN_WIDTH = 640
    SCREEN_HEIGHT = 480
    BLOCK_SIZE = 32.0
    BLOCK_HEIGHT = 32.0
    MOVE_SPEED = 100.0
    ROTATION_SPEED = 5.0

struct Level
    size : uint
    blocks : array<int>
    wall_tex : Image

struct Camera
    pos : float2
    angle : float
    fov : float
    plane_dist : float
    plane_size : float
    dir : float2
    right : float2

struct Framebuffer
    image : Image
    zbuffer : array<float> 

struct HitInfo
    dist : float
    x : int
    y : int
    offset : int

struct Sprite
    pos : float2
    size : float2
    on_ground : bool
    texture_id : uint

def create_framebuffer(width : int; height : int) : Framebuffer
    var f : Framebuffer
    f.image <- create_image(width, height)
    f.zbuffer |> resize(width)
    for i in range(0, width)
        f.zbuffer[i] = 1e23
    return <- f

def clear_zbuffer(var fb : Framebuffer)
    for i in range(0, length(fb.zbuffer))
        fb.zbuffer[i] = 1e23

def set_pixel(var fb : Framebuffer; x : int; y : int; color : uint)
    fb.image |> set_pixel(x, y, color)
    return

def set_depth(var fb : Framebuffer; x : int; depth : float)
    fb.zbuffer[x] = depth

def depth_test(var fb : Framebuffer; x : int; depth : float) : bool
    let zbuf_depth = fb.zbuffer[x]
    if (zbuf_depth < depth)
        return false
    fb.zbuffer[x] = depth
    return true

def ortho_vec2(v : float2) : float2
    return float2(-v.y, v.x)

def recalc_vectors(var res : Camera)
    res.dir = float2(cos(res.angle), sin(res.angle))
    res.right = ortho_vec2(res.dir)

def create_camera(pos : float2; angle : float; fov : float) : Camera
    var res : Camera
    res.pos := pos
    res.angle := angle
    res.fov := fov
    res.plane_dist := 1.f
    res.plane_size := tan(fov * PI /(2.0 * 180.0))
    res |> recalc_vectors
    return res

def get_direction(var cam : Camera) : float2
    return float2(cos(cam.angle), sin(cam.angle))

def trace_ray(var level : Level const; origin : float2; dir : float2; var out : HitInfo) : bool
    let INF = 1e23
    let cell_size = float2(BLOCK_SIZE, BLOCK_SIZE)
    let step_dir = float2(sign(dir.x), sign(dir.y))
    let cell_count = float2(float(level.size), float(level.size))
    var cell = floor(origin/cell_size)
    var t = 0.0
    var steps = 100
    while steps > 0 && cell.x >= 0.f && cell.x < cell_count.x && cell.y >= 0.f && cell.y <= cell_count.y  
        steps -= 1
        //r = o + t * d
        var x_plane = (cell.x + step_dir.x) * cell_size.x
        var y_plane = (cell.y + step_dir.y) * cell_size.y
        
        if step_dir.x < 0.0
            x_plane += cell_size.x - 0.0001
        if step_dir.y < 0.0
            y_plane += cell_size.y - 0.0001

        let tx = (abs(dir.x) > 0.00001)? (x_plane - origin.x)/dir.x : INF
        let ty = (abs(dir.y) > 0.00001)? (y_plane - origin.y)/dir.y : INF
        
        var hit_x = false
        if tx < ty
            t = tx
            hit_x = true
        else
            t = ty
        
        t += 0.00001

        let hit_pos = origin + t * dir
        cell = floor(hit_pos/cell_size)

        let x_ind = int(cell.x)
        let y_ind = int(cell.y)
        let arr_index = y_ind * int(level.size) + x_ind

        if arr_index < 0 || arr_index >= int(level.size * level.size)
            return false

        if level.blocks[arr_index] != 0
            out.dist = t
            out.x = x_ind
            out.y = y_ind
            let cell_pos = cell * cell_size
            out.offset = int((!hit_x)? (hit_pos.x - cell_pos.x) : (hit_pos.y - cell_pos.y))
            return true

    return false

def draw_2d(var camera : Camera; var level : Level)
    let VEC_LENGTH = 20.f
    let RED = 0x00FF0000
    let GREEN = 0x0000FF00
    let dir = camera.dir
    let orth = camera.right
    let start = camera.pos
    let dir_end = start + VEC_LENGTH * dir
    let orth_end = start + (VEC_LENGTH/2.0) * orth
    line(start.x, start.y, dir_end.x, dir_end.y, RED)
    line(start.x, start.y, orth_end.x, orth_end.y, GREEN)

    let rays_count = 10
    let delta = 2.0 * camera.plane_size/float(rays_count)

    for i in range(0, rays_count)
        let s = float(i) - 5.0
        let ray_dir = normalize(delta * s * camera.right + camera.dir)
        
        var hit : HitInfo
        var ray_end : float2

        if level |> trace_ray(start, ray_dir, hit)
            ray_end = start + ray_dir * hit.dist
        else
            ray_end = start + ray_dir * 1000.0

        line(start.x, start.y, ray_end.x, ray_end.y, 0x000000FF)

def draw_2d(var level : Level)
    let bsize = int(BLOCK_SIZE)
    let level_size = int(level.size) * bsize
    let WHITE = 0x00FFFFFF
    for i in range(0, int(level.size))
        let x = (i+1) * bsize 
        line(x, 0, x, level_size, WHITE)
        line(0, x, level_size, x, WHITE)
    
    for x in range(0, int(level.size))
        for y in range(0, int(level.size))
            let ix = y * int(level.size) + x 
            if level.blocks[ix] != 0
                fill_rect(x * bsize, y*bsize, bsize, bsize, 0x00c0c0c0)


def draw_3d(var camera : Camera const; var level : Level const; var framebuffer : Framebuffer)
    let rays_count = SCREEN_WIDTH
    let delta = 2.0 * camera.plane_size/float(rays_count)
    
    let SKY_COLOR = 0xFF0000CC
    let FLOOR_COLOR = 0xFFA0A0A0

    for i in range(0, rays_count)
        let s = delta * (float(i) - float(SCREEN_WIDTH/2))
        let ray_dir = normalize(s * camera.right + camera.dir)
        
        var hit : HitInfo

        if level |> trace_ray(camera.pos, ray_dir, hit)
            let plane_dist = sqrt(camera.plane_dist * camera.plane_dist + s*s)
            let slice_height = int((plane_dist * BLOCK_HEIGHT/hit.dist) * float(SCREEN_HEIGHT) * 3.0/4.0)
            let tex_start = (SCREEN_HEIGHT - slice_height)/2
            let y_start = max(tex_start, 0)
            let y_end = min(y_start + slice_height, SCREEN_HEIGHT);
            let slice_coef = float(BLOCK_HEIGHT)/float(slice_height)

            framebuffer |> set_depth(i, hit.dist) //for sprites

            for y in range(0, y_start)
                framebuffer |> set_pixel(i, y, SKY_COLOR)
            for y in range(y_start, y_end)
                let tex_y = int(float(y - tex_start) * slice_coef)
                let tex_color = level.wall_tex |> get_pixel(hit.offset, tex_y)
                framebuffer |> set_pixel(i, y, tex_color)
            for y in range(y_end, SCREEN_HEIGHT)
                framebuffer |> set_pixel(i, y, FLOOR_COLOR)
        else
            for y in range(0, SCREEN_HEIGHT/2)
                framebuffer |> set_pixel(i, y, SKY_COLOR)
            for y in range(SCREEN_HEIGHT/2, SCREEN_HEIGHT)
                framebuffer |> set_pixel(i, y, FLOOR_COLOR)
    return

def draw_sprite(var framebuffer : Framebuffer; var camera : Camera const; var sprite : Sprite const; var sprite_tex : ImageHandle)
    let camera_to_sprite = sprite.pos - camera.pos
    let right_vec = normalize(ortho_vec2(camera_to_sprite))

    var sprite_left = camera_to_sprite - sprite.size.x/2.0 * right_vec
    var sprite_right = camera_to_sprite + sprite.size.x/2.0 * right_vec

    
    //project on camera plane
    let t_left = dot(camera.dir, sprite_left)
    let t_right = dot(camera.dir, sprite_right)

    if (t_left < 1.0 || t_right < 1.0)
        return

    let length_before = length(sprite_left)
    sprite_left /= t_left
    sprite_right /= t_right
    let length_after = length(sprite_left)

    let sprite_height = int(sprite.size.y * length_after/length_before * float(SCREEN_HEIGHT) * 3.0/4.0)
    let wall_height = int(BLOCK_HEIGHT * length_after/length_before * float(SCREEN_HEIGHT) * 3.0/4.0)

    let x1 = float(SCREEN_WIDTH/2) * dot(sprite_left, camera.right) + float(SCREEN_WIDTH/2)
    let x2 = float(SCREEN_WIDTH/2) * dot(sprite_right, camera.right) + float(SCREEN_WIDTH/2)
    
    let x_tex_start = int(min(x1, x2))
    let x_tex_end = int(max(x1, x2))
    
    let x_start = clamp(x_tex_start, 0, SCREEN_WIDTH)
    let x_end = clamp(x_tex_end, 0, SCREEN_WIDTH)
    
    let floor_pos = SCREEN_HEIGHT/2 + wall_height/2
    var y_tex_start : int
    var y_tex_end : int
    
    if !sprite.on_ground
        y_tex_start = SCREEN_HEIGHT/2 - sprite_height/2
        y_tex_end = y_tex_start + sprite_height
    else
        y_tex_start = floor_pos - sprite_height
        y_tex_end = floor_pos
    

    let y_start = max(y_tex_start, 0)
    let y_end = min(y_tex_end, SCREEN_HEIGHT)

    let tex_size_x = float(sprite_tex.width)/float(x_tex_end - x_tex_start)
    let tex_size_y = float(sprite_tex.height)/float(y_tex_end - y_tex_start)

    for x in range(x_start, x_end)
        if !depth_test(framebuffer, x, length_before)
            continue
        
        let x_tex = int(float(x - x_tex_start) * tex_size_x) 

        for y in range(y_start, y_end)
            let y_tex = int(float(y - y_tex_start) * tex_size_y)
            let color = sprite_tex |> get_pixel(x_tex, y_tex)
            if (color & 0xFF000000u) != 0u
                framebuffer |> set_pixel(x, y, color)

    return

def move(var cam : Camera; forward : float; right : float; var level : Level const)
    let new_pos = cam.pos + forward * cam.dir + right * cam.right 
    let cell_x = (new_pos.x/BLOCK_SIZE)
    let cell_y = (new_pos.y/BLOCK_SIZE)
    
    if cell_x < 0.0 || cell_x >= float(level.size)
        return
    if cell_y < 0.0 || cell_y >= float(level.size)
        return

    let level_ix = int(cell_y) * int(level.size) + int(cell_x)
    if level_ix < 0 || level_ix >= length(level.blocks) || level.blocks[level_ix] != 0 
        return


    cam.pos = new_pos

def move(var cam : Camera; move_dir : float2; var level : Level const)
    cam |> move(move_dir.x, move_dir.y, level)

def rotate(var cam : Camera; dangle : float)
    cam.angle += dangle
    let pi2 = 2.0 * PI
    if cam.angle > pi2
        cam.angle -= pi2
    if cam.angle < 0.0
        cam.angle += pi2
    cam |> recalc_vectors

struct Projectile
    sprite : Sprite 
    velocity : float2
    time : float

struct ProjectileManager
    missle_tex : ImageHandle 
    alive : array<Projectile>
    cooldown : float

def init_projectiles(tex_name : string)
    var res : ProjectileManager
    res.cooldown = 0.0
    res.alive |> reserve(10)
    res.missle_tex <- create_managed_image(tex_name)
    return <- res

def spawn(var projectiles : ProjectileManager; pos : float2; dir : float2)
    if (projectiles.cooldown > 0.0 || length(projectiles.alive) > 10)
        return

    let PROJ_VELOCITY = 300.0
    let COOLDOWN_TIME = 0.2
    let TTL = 0.5

    projectiles.cooldown = COOLDOWN_TIME
    var new_proj : Projectile
    new_proj.sprite.pos = pos + 5.0 * dir
    new_proj.sprite.size = float2(3, 3)
    new_proj.sprite.on_ground = false
    new_proj.velocity = PROJ_VELOCITY * normalize(dir)
    new_proj.time = TTL
    
    projectiles.alive |> push(new_proj)

def draw(var fb : Framebuffer; var camera : Camera const; var projectiles : ProjectileManager)
    for elem in projectiles.alive
        fb |> draw_sprite(camera, elem.sprite, projectiles.missle_tex)

struct Enemy
    sprite : Sprite
    is_dead : bool

struct EnemyManager
    alive : array<Enemy>
    dead : array<Sprite>
    alive_tex : ImageHandle
    dead_tex : ImageHandle

def init_enemies(alive_name : string; dead_name : string)
    var manager : EnemyManager
    manager.alive_tex <- create_managed_image(alive_name)
    manager.dead_tex <- create_managed_image(dead_name)
    return <- manager

def spawn(var enemies : EnemyManager; pos : float2)
    let ENEMY_SIZE = float2(16, 16)
    var new_enemy : Enemy
    new_enemy.sprite.pos = pos
    new_enemy.sprite.size = ENEMY_SIZE
    new_enemy.sprite.on_ground = true
    new_enemy.is_dead = false
    enemies.alive |> push(new_enemy)

def draw(var fb : Framebuffer; var camera : Camera; var enemies : EnemyManager)
    for elem in enemies.alive
        fb |> draw_sprite(camera, elem.sprite, enemies.alive_tex)
    for elem in enemies.dead
        fb |> draw_sprite(camera, elem, enemies.dead_tex)

def update(var projectiles : ProjectileManager; var level : Level const; var enemies : EnemyManager; dt : float)
    var processed : array<Projectile>
    processed |> reserve(10)

    for elem in projectiles.alive
        elem.time -= dt
        if elem.time <= 0.0
            continue
        elem.sprite.pos += elem.velocity * dt
        
        var projectile_destroyed = false 

        for enemy in enemies.alive
            let delta = length(elem.sprite.pos - enemy.sprite.pos)
            if (delta < (elem.sprite.size.x + enemy.sprite.size.x)/2.0)
                enemy.is_dead = true
                projectile_destroyed = true
                break
        if !projectile_destroyed
            processed |> push(elem)

    projectiles.alive <- processed
    projectiles.cooldown = max(projectiles.cooldown - dt, 0.0)

def update(var enemies : EnemyManager; var level : Level const; dt : float)
    var processed : array<Enemy>
    processed |> reserve(length(enemies.alive))
    for elem in enemies.alive
        if elem.is_dead
            enemies.dead |> push(elem.sprite)
        else
            processed |> push(elem)

    enemies.alive <- processed

var
    framebuffer : Framebuffer
    player_camera : Camera
    level : Level
    show_2d = false
    projectiles : ProjectileManager
    enemies : EnemyManager

[export]
def initialize
    framebuffer <- create_framebuffer(SCREEN_WIDTH, SCREEN_HEIGHT)

    level.size = 8u
    level.blocks <- to_array_move([[int[]
        0; 0; 0; 0; 0; 0; 0; 0;
        0; 1; 0; 0; 0; 1; 0; 0;
        0; 0; 1; 0; 0; 0; 1; 0;
        0; 0; 0; 0; 0; 0; 0; 0;
        0; 0; 0; 0; 0; 0; 0; 0;
        0; 1; 0; 0; 0; 1; 0; 0;
        0; 0; 1; 0; 0; 0; 1; 0;
        0; 0; 0; 0; 0; 0; 0; 0]])

    level.wall_tex <- create_image("wall.png")

    player_camera := create_camera(float2(10.f, 10.f), 0.f, 90.f)

    projectiles <- init_projectiles("missle.png")
    enemies <- init_enemies("enemy.png", "rip.png")
    enemies |> spawn(float2(200.0, 16.0))
    enemies |> spawn(float2(100.0, 150.0))

    print("{get_screen_width()} {get_screen_height()}\n")
    return

[export]
def act(dt : float)
    if get_key(VK_ESCAPE)
        schedule_quit_game()

    var move_dir := float2(0, 0)
    
    if get_key(VK_W)
        move_dir.x += 1.0
    if get_key(VK_S)
        move_dir.x -= 1.0
    if get_key(VK_A)
        move_dir.y -= 1.0
    if get_key(VK_D)
        move_dir.y += 1.0
    
    if get_key_press(VK_SPACE)
        show_2d = !show_2d

    if get_key(VK_E)
        projectiles |> spawn(player_camera.pos, player_camera.dir)

    var rotation = 0.0

    if get_key(VK_LEFT)
        rotation -= 1.f
    if get_key(VK_RIGHT)
        rotation += 1.f
    
    player_camera |> move(move_dir * MOVE_SPEED * dt, level)
    player_camera |> rotate(rotation * ROTATION_SPEED * dt)
    projectiles |> update(level, enemies, dt)
    enemies |> update(level, dt)
    return

[export]
def draw
    if show_2d
        let level_size = BLOCK_SIZE * float(level.size)
        let scale = float2(float(get_screen_width())/level_size, float(get_screen_height())/level_size)
        transform2d_scale(min(scale.x, scale.y), float2(0.0, 0.0))
        level |> draw_2d
        player_camera |> draw_2d(level)
        transform2d_pop()
    else
        fill_rect(0, 0, get_screen_width(), get_screen_height(), 0x00000000)
        
        framebuffer |> clear_zbuffer()
        player_camera |> draw_3d(level, framebuffer)

        framebuffer |> draw(player_camera, enemies)
        framebuffer |> draw(player_camera, projectiles)
        
        let scale = float(get_screen_height())/float(SCREEN_HEIGHT)
        let size = scale * float2(SCREEN_WIDTH, SCREEN_HEIGHT)
        let xoffset = max((float(get_screen_width()) - size.x)/2.0, 0.0)

        framebuffer.image |> draw_image(xoffset, 0.0, 0xFFFFFFFF, size)
    return