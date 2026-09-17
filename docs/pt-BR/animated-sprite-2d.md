# AnimatedSprite2D

[English](../animated-sprite-2d.md) | **Português (Brasil)**

Arraste o arquivo `.aseprite` do dock FileSystem para a propriedade **Sprite Frames** de um
AnimatedSprite2D e toque as animações como de costume: `$AnimatedSprite2D.play("walk_down")`.

- As animações se chamam `{tag}_{direction}`, sem o sufixo de loop: a tag `idle_loop` gera
  `idle_down`, `idle_left_up`, e assim por diante.
- A velocidade da animação é 1 / o frame mais curto da tag, e cada frame mantém sua duração relativa
  a ele, então um `speed_scale` de 1 toca na velocidade do Aseprite.
- Uma animação em loop nunca emite `animation_finished`. O código pode diferenciar os loops com
  `sprite_frames.get_animation_loop("idle_down")`.
- Salvar o arquivo no Aseprite atualiza as animações quando o Godot recupera o foco.
- O SpriteFrames é um recurso importado: mudanças feitas no editor de SpriteFrames se perdem na
  próxima importação. *Make Unique* gera uma cópia editável, que deixa de ser atualizada.
