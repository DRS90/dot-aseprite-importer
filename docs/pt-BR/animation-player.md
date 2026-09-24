# AnimationPlayer

[English](../animation-player.md) | **Português (Brasil)**

No inspetor do AnimatedSprite2D, em **AnimatedSprite2D**, a seção **AnimationPlayer** vincula um
player: clique em **Assign...** e escolha um AnimationPlayer da cena. Cada animação do SpriteFrames
do sprite vira uma animação de mesmo nome na biblioteca global do player, com duas trilhas no
sprite, `animation` e `frame`, cujas chaves ficam nos tempos dos frames do Aseprite e que ficam em
loop como a animação do SpriteFrames. Reproduza-as com `$AnimationPlayer.play("run")`.

- As animações são sincronizadas de novo quando o arquivo `.aseprite` é reimportado (na cena aberta)
  e quando uma cena é aberta, se algo mudou. **Sync animations** força uma sincronização. Uma
  sincronização marca a cena como modificada: salve-a.
- Uma sincronização substitui só as trilhas `animation` e `frame` do sprite. Trilhas que você
  adiciona às mesmas animações (sons, hitboxes, chamadas de método) são mantidas. Quando uma tag ou
  direção some, a animação dela perde as trilhas do sprite e só é apagada se não sobrar mais nada
  nela.
- Vários sprites podem compartilhar um AnimationPlayer (por exemplo, um corpo e uma arma de arquivos
  diferentes): cada sprite tem suas próprias trilhas.
- Enquanto um AnimationPlayer controla o sprite, não reproduza também o AnimatedSprite2D (`play()`
  ou *Autoplay on Load*).
- O vínculo fica nos metadados do sprite e é salvo com a cena. A cena só contém nós e recursos
  nativos do Godot, então o jogo não precisa do addon para rodar.
- Nós dentro de uma cena instanciada são sincronizados quando essa cena é aberta. **Clear** desfaz o
  vínculo com o player e mantém as animações já gravadas.
- As animações são gravadas num arquivo de recurso próprio. Em *Project Settings > Dot
  Aseprite Importer > Animation Player*, **External Library** (ativado) decide se isso acontece, e
  **Library Path** diz onde: `{scene_dir}` e `{scene}` vêm da cena que contém o player,
  então o padrão é `main.tscn` → `main_animations.tres` ao lado dela. A cena passa a ter uma linha
  `ext_resource` no lugar das animações: a demo em `examples/` tem 17 linhas em vez de 1107.
  **Desative External Library** para manter as animações dentro da cena, que é o que o Godot faz
  por conta própria. O arquivo é gravado quando a cena é salva.
- Uma biblioteca que já é um arquivo nunca é movida, mesmo que a configuração indique outro
  caminho, e desativar External Library não a traz de volta para dentro da cena (para isso, limpe o
  `resource_path` dela).
  Uma biblioteca embutida na cena vai para o arquivo na próxima sincronização. Se esse arquivo já
  existir, ele prevalece, mas as animações que só a embutida tinha são copiadas para ele, então as
  trilhas que você adicionou não se perdem. Uma cena que nunca foi salva não tem caminho de onde
  derivar o nome, então a biblioteca dela fica embutida até você salvar a cena e sincronizar de
  novo. Em caso de erro, a biblioteca fica embutida e o motivo é informado. Duas cenas que indicam o
  mesmo arquivo gravam no mesmo arquivo.
