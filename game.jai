#import "Basic";
#import "Math";

Input :: #import "Input";
#import "Window_Creation"; 
Simp :: #import,dir "lib/Simp";

Arena :: struct
{
    base: *void;
    offset: s64;
    size: s64;
}

TileType :: enum
{
    EMPTY;
    WALL;
}

Projectile :: struct
{
    is_alive: bool;
    pos: Vector2;
    velocity: Vector2;
}

Rect :: struct
{
    top_left: Vector2;
    extent: Vector2;
}

Room :: union
{
    grid: [ROOM_HEIGHT] [ROOM_WIDTH] TileType;
    flat: [ROOM_WIDTH * ROOM_HEIGHT] TileType;
}

WIDTH :: 320;
HEIGHT :: 180;
PIXEL_SIZE :: 6;
TILE_SIZE :: 10;
WINDOW_WIDTH :: WIDTH * PIXEL_SIZE;
WINDOW_HEIGHT :: HEIGHT * PIXEL_SIZE;
ROOM_WIDTH :: WIDTH / TILE_SIZE;
ROOM_HEIGHT :: HEIGHT / TILE_SIZE;

SHOOT_DELAY :: 0.3;

make_arena :: (size: s64) -> Arena
{
	arena: Arena;
	arena.base = alloc(size);
    arena.size = size;
    return arena;
}

arena_push :: (arena: *Arena, size: s64) -> *void
{
	assert(arena.offset + size <= arena.size);
	return_pointer := arena.base + arena.offset;
    arena.offset += size;
    return return_pointer;
}

draw_sprite :: (sprite: Simp.Texture, pos: Vector2, origin := Vector2.{ 0.5, 0.5 })
{
    half_width: float = cast(float) sprite.width / 2;
    half_height: float = cast(float) sprite.height / 2;

    top_left     := pos + Vector2.{ -half_width, -half_height };
    top_right    := pos + Vector2.{  half_width, -half_height };
    bottom_right := pos + Vector2.{  half_width,  half_height };
    bottom_left  := pos + Vector2.{ -half_width,  half_height };

    Simp.set_shader_for_images(*sprite);
    Simp.immediate_quad(top_left, top_right, bottom_right, bottom_left);
}

sign :: (value: $T) -> T
{
    if value > 0 return 1;
    if value < 0 return -1;
    return 0;
}

check_collision :: (a: Rect, b: Rect) -> bool
{
    overlap_x := false;
    overlap_y := false;

    if a.top_left.x + a.extent.x > b.top_left.x && b.top_left.x + b.extent.x > a.top_left.x  overlap_x = true;
    if a.top_left.y + a.extent.y > b.top_left.y && b.top_left.y + b.extent.y > a.top_left.y  overlap_y = true;

    if overlap_x && overlap_y return true;
    else return false;
}

collides_with_any_tile :: (pos: Vector2, size: Vector2, room: Room) -> bool
{
    rect := Rect.{ pos - (size/2), size };
    for room.flat
    {
        if it == TileType.EMPTY continue;
        tile_origin := Vector2.{ xx(it_index % ROOM_WIDTH), xx(it_index / ROOM_WIDTH) } * TILE_SIZE;
        tile_rect := Rect.{ tile_origin, Vector2.{ TILE_SIZE, TILE_SIZE } };
        if check_collision(tile_rect, rect) return true;
    }
    return false;
}

main :: ()
{
    prev_time := seconds_since_init();

	perm_arena := make_arena(2048);

	room: Room;
	projectiles: [32] Projectile;

    move_speed :: 50.0;
    guy_size :: Vector2.{ 8.0, 8.0 };
	guy_pos := Vector2.{ WIDTH / 2.0, HEIGHT / 2.0 };

    shoot_cooldown := 0.0;


    prev_user_input: [512] bool;
    user_input: [512] bool;

    window := create_window(WINDOW_WIDTH, WINDOW_HEIGHT, "window simp");

    projectile_sprite: Simp.Texture;
    guy_sprite: Simp.Texture;
    wall_sprite: Simp.Texture;

    Simp.set_render_target(window);

    assert(Simp.texture_load_from_file(*projectile_sprite, "data/sprites/projectile.png"));
    assert(Simp.texture_load_from_file(*guy_sprite, "data/sprites/guy.png"));
    assert(Simp.texture_load_from_file(*wall_sprite, "data/sprites/wall.png"));

    render_target := Simp.texture_create_render_target(WIDTH, HEIGHT, .RGBA8);

    quit := false;
    while !quit {
        memset(*user_input, 0, size_of(type_of(user_input)));

        Input.update_window_events();

        for Input.events_this_frame {
            if it.type == {
              case .QUIT;
                quit = true;
            }
        }

        for Input.input_button_states {
            if it & .DOWN {
                user_input[it_index] = true;
            }
        }

        time := seconds_since_init();
        delta_time := cast(float)(time - prev_time);
        prev_time = time;

        if user_input[Input.Key_Code.ESCAPE] break;

        move_dir : Vector2;

        if user_input[#char "R"]  move_dir.y += 1;
        if user_input[#char "L"]  move_dir.y -= 1;
        if user_input[#char "N"]  move_dir.x += 1;
        if user_input[#char "S"]  move_dir.x -= 1;

        move_dir = normalize(move_dir);

        prev_guy_pos := guy_pos;
        moved_guy_pos := prev_guy_pos + move_dir * move_speed * delta_time;

        // Collisions

        // Do x movement
        guy_pos.x = moved_guy_pos.x;
        if collides_with_any_tile(guy_pos, guy_size, room)
        {
            guy_pos.x = prev_guy_pos.x;
        }

        // Do y movement
        guy_pos.y = moved_guy_pos.y;
        if collides_with_any_tile(guy_pos, guy_size, room)
        {
            guy_pos.y = prev_guy_pos.y;
        }

        // Projectile / wall collision
        for room.flat
        {
            for *projectiles
            {
                projectile_size :: Vector2.{ 6.0, 6.0 };
                margin :: Vector2.{ 4.0, 4.0 };

                projectile_rect := Rect.{ it.pos - projectile_size / 2 + margin / 2, projectile_size - margin }; 
                tile_origin := Vector2.{ xx(it_index % ROOM_WIDTH), xx(it_index / ROOM_WIDTH) } * TILE_SIZE;
                tile_rect := Rect.{ tile_origin, Vector2.{ TILE_SIZE, TILE_SIZE } };
                if check_collision(projectile_rect, tile_rect)
                {
                    it.is_alive = false;
                }
            }
        }

        for *projectiles
        {
            projectile_size :: Vector2.{ 6.0, 6.0 };
            room_rect :: Rect.{ Vector2.{ 0, 0 }, Vector2.{ WIDTH, HEIGHT } };

            rect := Rect.{ it.pos - projectile_size / 2, projectile_size }; 
            if !check_collision(rect, room_rect)
            {
                it.is_alive = false;
            }
        }

        shoot_direction : Vector2;
        shoot_this_frame := false;


        if user_input[Input.Key_Code.ARROW_DOWN]
        {
			shoot_direction.y = 1;
            shoot_this_frame = true;
        }
        else if user_input[Input.Key_Code.ARROW_UP]
        {
			shoot_direction.y = -1;
            shoot_this_frame = true;
        }
        else if user_input[Input.Key_Code.ARROW_RIGHT]
        {
			shoot_direction.x = 1;
            shoot_this_frame = true;
        }
        else if user_input[Input.Key_Code.ARROW_LEFT]
        {
			shoot_direction.x = -1;
            shoot_this_frame = true;
        }

        if shoot_this_frame && shoot_cooldown > SHOOT_DELAY
        {
            shoot_cooldown = 0;

            projectile_found: *Projectile;
			for *projectiles
            {
                if it.is_alive continue;
				projectile_found = it;
            }
        	
            if projectile_found
            {
                projectile_found.pos = guy_pos + shoot_direction * 4;
                projectile_found.velocity = shoot_direction * 100;
                projectile_found.velocity.x -= shoot_direction.y * move_dir.x * move_speed / 2 * -sign(shoot_direction.y);
                projectile_found.velocity.y -= shoot_direction.x * move_dir.y * move_speed / 2 * -sign(shoot_direction.x);
                projectile_found.is_alive = true;
            }
        }

        for *projectiles
        {
            if !it.is_alive continue;
            it.pos += it.velocity * delta_time;
        }

		shoot_cooldown += delta_time;

        // Level editor
        //mouse_pos := Ray.GetMousePosition();
        //hovered_tile_coords := Vector2.{ floor(mouse_pos.x / (TILE_SIZE * PIXEL_SIZE)), floor(mouse_pos.y / (TILE_SIZE * PIXEL_SIZE)) };

        /*
        if Ray.IsMouseButtonDown(.MOUSE_BUTTON_LEFT) room.grid[xx hovered_tile_coords.y][xx hovered_tile_coords.x] = .WALL;
        if Ray.IsMouseButtonDown(.MOUSE_BUTTON_RIGHT) room.grid[xx hovered_tile_coords.y][xx hovered_tile_coords.x] = .EMPTY;
        */

		// Render

        Simp.set_render_target(*render_target, .LEFT_HANDED);
        Simp.clear_render_target(.08, .08, .15, 1);
        Simp.immediate_begin();

        draw_sprite(guy_sprite, guy_pos);

        for projectiles 
        {
            if !it.is_alive continue;
            draw_sprite(projectile_sprite, it.pos);
        }

        for room.flat
        {
            if it == .EMPTY  continue;
            draw_sprite(wall_sprite, Vector2.{ xx(it_index % ROOM_WIDTH), xx (it_index / ROOM_WIDTH) } * TILE_SIZE, Vector2.{ 0, 0 });
        }

/*
        if !Ray.IsMouseButtonDown(.MOUSE_BUTTON_RIGHT)
        {
            draw_sprite(wall_sprite, Vector2.{ xx hovered_tile_coords.x, xx hovered_tile_coords.y } * TILE_SIZE, Vector2.{ 0, 0 });
        }
        */

        Simp.immediate_flush();

        Simp.set_render_target(window, .LEFT_HANDED);
        Simp.immediate_begin();

        draw_sprite(render_target, Vector2.{ WINDOW_WIDTH, WINDOW_HEIGHT }, Vector2.{ 0, 0 });

        top_left     := Vector2.{ 0, 0 };
        top_right    := Vector2.{ WINDOW_WIDTH, 0 };
        bottom_right := Vector2.{ WINDOW_WIDTH, WINDOW_HEIGHT };
        bottom_left  := Vector2.{ 0, WINDOW_HEIGHT };

        Simp.set_shader_for_images(*render_target);
        Simp.immediate_quad(top_left, top_right, bottom_right, bottom_left);

        Simp.immediate_flush();
        Simp.swap_buffers(window);
    } 
}
