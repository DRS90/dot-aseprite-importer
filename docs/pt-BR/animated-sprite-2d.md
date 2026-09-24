# AnimatedSprite2D

[English](../animated-sprite-2d.md) | **Português (Brasil)**

Arraste o arquivo `.aseprite` do dock FileSystem para a propriedade **Sprite Frames** de um
AnimatedSprite2D e reproduza as animações como de costume: `$AnimatedSprite2D.play("run")`.

- As animações recebem o nome da tag, sem o sufixo de loop: a tag `idle_loop` gera `idle`. Um
  arquivo importado com `grid/directions` em `3x3` acrescenta a direção, então `idle_loop` gera
  `idle_down`, `idle_left_up` e assim por diante (`sprite_frames/animation_name`, padrão
  `{tag}_{direction}`).
- A velocidade da animação é 1 / o frame mais curto da tag, e cada frame mantém sua duração relativa
  a ele, então um `speed_scale` de 1 reproduz na velocidade do Aseprite.
- Uma animação em loop nunca emite `animation_finished`. O código pode diferenciar os loops com
  `sprite_frames.get_animation_loop("idle")`.
- Salvar o arquivo no Aseprite atualiza as animações quando o Godot recupera o foco.
- O SpriteFrames é um recurso importado: mudanças feitas no editor de SpriteFrames se perdem na
  próxima importação. *Make Unique* gera uma cópia editável, que deixa de ser atualizada.
