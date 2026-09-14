# Spanish pack review (for native-speaker SLP)

**What this is:** a careful line-by-line review of `assets/lang/es.json` (246 words: 192 core + 50 folder words + 4 folder tiles; ids and grid positions verified identical to `en.json`) against the English pack. This is a first-draft machine-assisted translation — the file itself is marked DRAFT — and it reads like one: the grammar is mostly correct, but several words are dictionary-correct yet not what a Spanish-speaking child would actually say, a few are mistranslations, and there are exact-duplicate labels on different tiles that will confuse motor planning.

**Overall confidence:** Medium-high on grammar and spelling (accents are correct throughout — qué, dónde, cuál, adiós, autobús, música, fácil/difícil; "solo" correctly unaccented per RAE; no typos and no English words left untranslated). Medium on word choice — roughly 1 in 8 tiles needs a change or a decision, concentrated in verbs, feelings/body states, and duplicates. Low on two structural questions below (verb-person convention, TTS locale) that only you can settle.

**The ttsLocale question (please read first):** the pack declares `ttsLocale: "es-ES"`, but the labels lean clearly Latin American — *jalar* (pull), *carro* (car), *chistoso* (funny), *enojado* (angry), *resbaladilla* (slide), *jugo* (juice), *cuarto* (bedroom), *lastimado* (hurt), *plátano* (banana). That LatAm lean is **correct for the audience** (VidaCare serves US Latino families, largely Mexican/Central American). The mismatch is the voice: an es-ES voice will pronounce these with Peninsular ceceo (*grathias*), which sounds foreign to the families using them. **Recommendation: change ttsLocale to `es-US`** (falling back to `es-MX` if es-US is unavailable on-device), and keep the LatAm-leaning labels. Do not "fix" the labels toward Spain Spanish — that would move away from the families.

**A note on duplicates:** several flags below are exact-duplicate labels on different tiles (*no*/*no*, *perdón*/*perdón*, *suave*/*suave*, *fuerte*/*fuerte*). Grid positions differ so motor memory still works, but identical spoken output from two tiles is a real usability problem. Each flag proposes a way out.

---

## Flagged words

EN id | EN label | current ES | recommended | reason
---|---|---|---|---
`core.stop` | stop | **alto** | **para** | "Alto" primarily means "tall." As a command it only works via the Mexican stop-sign convention ("ALTO" on signs) — ambiguous and confusing for a child. "Para" is the imperative children actually hear for "stop." Note: this creates a second "para" tile (`core.for` = para); if that's unacceptable, the fallback is "basta" ("stop it!"), which is very natural child speech but narrower in meaning. Your call.
`core.dont` | don't | **no** | keep **no** — but decide how to disambiguate | "No" is the correct verb negator ("no quiero", "no más"), but it is pixel-identical to `core.no` ("no"). Two identical tiles in different rows is a motor-planning hazard. Options: accept it (icons/positions differ: 👎 vs ✖️), or drop one of the two concepts. Needs your decision — there is no better single word.
`core.make` | make | **crear** | **hacer** | "Crear" means "to create" in the artistic/inventive sense. A child "making" cookies, a mess, or a drawing says "hacer," not "crear." This is a straight mistranslation for everyday use.
`core.get` | get | **tomar** | **agarrar** | "Tomar" means "to drink" or "to take in hand" — it mistranslates "get" (obtain/grab) and it collides with the drink tile. "Agarrar" is the everyday Latin American word for "get/grab." (Do NOT use "coger" — it is vulgar in most of Latin America.)
`core.drink` | drink | **beber** | **tomar** | Children say "tomar," not "beber" ("quiero tomar agua"). "Beber" is correct but formal/adult. This pairs with the `core.get` fix above, which frees up "tomar."
`core.do` | do | hacer | keep **hacer** | "Hacer" is correct for "do" — but once `core.make` becomes "hacer" too, two tiles say "hacer." Spanish genuinely collapses make/do into one verb, so some duplication may be unavoidable; still, flagging it so you can decide deliberately (some packs accept it, some drop one tile).
`core.me` | me | **mí** | **me** | Bare "mí" is ungrammatical without a preposition — a child composing "help me" gets "ayuda mí" ✗. The clitic "me" composes correctly ("ayúdame," "mírame") and the TTS speaks it fine as a standalone tile.
`core.on` | on | **encendido** | **prender** | "Encendido" is an adjective ("powered on") sitting in a verb slot, and it doesn't compose ("yo encendido" ✗). The 💡 emoji indicates the intent is "turn the light on," so the infinitive "prender" fits the verb pattern ("quiero prender [la luz]"). If the intent was the preposition "on" instead, the word should be "encima" — please confirm intent.
`core.off` | off | **apagado** | **apagar** | Same as above: adjective in a verb slot; "apagar" is the verb a child needs. (If preposition intent: there is no clean one-word tile — "off" overlaps `core.out`/`core.down` — so the light-switch reading is almost certainly right.)
`core.help` | help | **ayuda** | **ayudar** | "Ayuda" is the noun ("la ayuda") or an exclamation ("¡ayuda!"). As a verb tile in a row of infinitives it should be "ayudar" ("quiero ayudar"). That said, a child in distress shouts "¡ayuda!" — if this tile is meant as the distress cry rather than the verb, keep it. Your call.
`core.finished` | finished | **terminado** | **terminé** | "Terminado" is masculine — a girl would need "terminada," and the tile can't do both. The first-person preterite "terminé" ("I finished") is gender-neutral, is what children actually say, and matches the quiero/necesito convention below.
`core.excuseme` | excuse me | **perdón** | **disculpa** | Exact duplicate of `core.sorry` ("perdón"). "Disculpa" works both to get attention and to apologize lightly, and it keeps the two tiles distinct.
`core.gentle` | gentle | **suave** | **despacio** | Exact duplicate of `core.soft` ("suave"). Caregivers saying "gentle" to a child say "despacito" — "despacio" is the clean tile form.
`core.hurray` | hurray | **viva** | **yupi** | "Viva" means "long live" (¡viva México!). The child cheer is "¡yupi!" (fallback: "hurra").
`core.funny` | funny | chistoso | **gracioso** | Paired swap with `feel.silly` below: "gracioso" is the neutral, pan-Hispanic descriptor for "funny" (also correct in Spain); "chistoso" is better reserved for the goofy *feeling*.
`feel.silly` | silly | **gracioso** | **chistoso** | "Gracioso" reads as "funny/amusing" (a descriptor), not the goofy *feeling* of being silly. Latin American kid speech for "I'm being silly/goofy" is "chistoso" ("ando chistoso").
`core.loud` | loud | **fuerte** | **ruidoso** (tentative) | Exact duplicate of `core.strong` ("fuerte"). "Ruidoso" disambiguates — but honestly "fuerte" is the more natural word for loud ("habla fuerte"), so I'm torn; pick the distinction or the naturalness, not both.
`core.scary` | scary | **tenebroso** | **da miedo** | "Tenebroso" is literary — it means gloomy/eerie (a "tenebroso" alley). A child says "da miedo." Two-word tile, but it's the real phrase.
`core.hungryd` | hungry | **hambriento** | **tengo hambre** | "Hambriento" means famished/starving and is formal — no child says "estoy hambriento." Children say "tengo hambre." (Same for the folder duplicate below; EN duplicates it too, so change both or neither.)
`food.hungry` | hungry | **hambriento** | **tengo hambre** | Same as above — keep the two "hungry" tiles consistent with each other.
`food.thirsty` | thirsty | **sediento** | **tengo sed** | "Sediento" means parched and is formal. Children say "tengo sed."
`food.banana` | banana | **plátano** | **banana** | Real confusion risk: in much of Latin America "plátano" means *plantain* (the large cooking banana), not the sweet banana a child eats. "Banana" is the everyday word for US Latino families. (In Spain "plátano" = banana — another reason the es-ES locale is wrong for this pack.)
`food.yucky` | yucky | **asqueroso** | **qué asco** | "Asqueroso" ("disgusting") is strong and adult-register. A child says "¡qué asco!" (Mexican kids also say "¡guácala!" — "qué asco" is the neutral choice).
`feel.love` | love | **amor** | **te quiero** | "Amor" is the noun — a child expressing love means "I love *you*," directed at the listener. "Te quiero" is the functional phrase. (Note: it's second-person-directed; there is no clean person-neutral alternative.)
`core.some` | some | **algo** | **un poco** | "Algo" means "something," not "some (of it)." A child asking for "some" (water, crackers) means "un poco." For countable plurals the word would be "algunos/as" — no single tile covers both; "un poco" is the most useful.
`core.stand` | stand | **levantarse** | **pararse** | "Levantarse" means "get up" (from bed) — it overlaps waking up. "Stand up" in Latin American child speech is "párate," so the infinitive is "pararse." (Spain: "ponerse de pie.")
`core.sit` | sit | sentarse | keep **sentarse** (minor) | The reflexive infinitive breaks the plain-infinitive pattern, but "sentar" alone reads transitive (to seat *someone*). "Sentarse" is clearer — flagging only so the inconsistency is a conscious choice.
`core.light` | light | ligero | keep **ligero** — confirm intent | The 🔦 (flashlight) emoji suggests this might mean "a light/lamp" rather than "not heavy." If it's the adjective (not heavy), "ligero" is correct. If it's the noun, it should be "luz." Please confirm.
`core.take` | take | llevar | keep **llevar** | Fine as "take away / carry," and it pairs coherently once `core.get` becomes "agarrar." No change — listed so the get/take pair is reviewed together.
`core.want` / `core.need` / `core.like` | want / need / like | quiero / necesito / me gusta | keep — deliberate exception | These three are conjugated (1st person) while every other verb is infinitive. Keep them: they're the highest-frequency self-advocacy words and this is how the child actually speaks ("quiero agua," "me gusta"). But document it as a deliberate convention (see open questions), because `core.finished` → "terminé" follows the same logic.
`core.his` / `core.her` / `core.their` / `core.our` | his / her / their / our | de él / de ella / de ellos / de nosotros | keep — deliberate | "Su" is the natural possessive, but it would make his/her/their three identical "su" tiles. The explicit "de él" forms keep tiles distinct and match child possessive constructions ("es de él" = "it's his"). Conscious tradeoff — confirm you're comfortable with it.

**Duplicates resolved as by-design (no change):** `core.playv` ("jugar") vs the `folder.play` tile ("jugar") — the folder tile is the entry point, the verb is the word; `core.tired`/`feel.tired` ("cansado") and `core.sick`/`feel.sick` ("enfermo") — English duplicates these too.

---

## Looks good (spot-checked, no concerns)

- **Pronouns:** yo, tú, él, ella, mí→(see flag), eso for "it" (the pragmatic choice — Spanish usually drops it, but a tile is needed and "eso" is what children point with).
- **Question words:** all correct with accents — qué, dónde, quién, cuándo, cómo, por qué, cuál, de quién.
- **Verb infinitives (rows 8–13):** ver, mirar, escuchar, decir, contar, preguntar, jugar, trabajar, dormir, caminar, abrir, cerrar, girar, empujar, soltar, romper, arreglar, limpiar, cocinar, leer, escribir, cantar, bailar, correr, saltar, trepar, montar, comprar, encontrar, perder, esconder, mostrar, esperar, intentar, empezar, pensar, saber, aprender, recordar, olvidar, soñar, reír, llorar, volar — all correct, consistent infinitives, everyday words.
- **Social words:** hola, adiós, por favor, gracias, sí, más, otra vez, está bien, buenos días, buenas noches, mi turno, tu turno, cuidado, ups, uy, guau — all natural.
- **Places & little words:** aquí/allí, arriba/abajo, en, fuera, izquierda/derecha, casa, escuela, tienda, baño, playa, zoológico, autobús; y, pero, o, porque, con, para, a, de, muy, también, solo, solamente, acerca de, cada — all correct.
- **Food nouns:** manzana, galleta, pan, queso, huevo, agua, leche, jugo, pizza, espagueti — the common everyday words. (Jugo/queso/huevo all LatAm-appropriate.)
- **People:** mamá, papá, abuela, abuelo, hermana, hermano, bebé, tía — all correct.
- **Play:** pelota, juguete, libro, juego, música, afuera, parque, nadar, dibujar, tele, libro, rompecabezas — all the words children actually use ("tele" not "televisión" — good).
- **Feelings:** emocionado, asustado, enojado, cansado, enfermo, lastimado, tranquilo, orgulloso, aburrido, valiente — correct; *enojado* and *lastimado* are the right Latin American choices (Spain would say *enfadado*/*herido*).
- **Spelling/accents:** no typos found; accents correct throughout; "solo" correctly written without accent (RAE 2010+); nothing left in English ("shhh" is onomatopoeia, fine).

---

## Open questions for the SLP

1. **TTS locale: `es-ES` vs `es-US`.** The labels are Latin American; the voice is Peninsular. For US Latino families this is backwards. Recommend `es-US` (fallback `es-MX`). If the foundation ever serves families in Spain, that's a separate pack, not a tweak.
2. **Verb-person convention.** The pack mixes first-person (quiero, necesito, me gusta, →terminé) with infinitives (comer, ir, jugar…). My recommendation: keep it, as a documented rule — *the child's own voice* (want/need/like/finished) is conjugated; everything else is infinitive. Confirm, or normalize all to infinitives (querer, necesitar) if you prefer strict consistency.
3. **Masculine defaults.** Adjectives and articles default masculine throughout: un/el, pequeño, bueno/malo, nuevo, limpio, cansado, enfermo, favorito, bonito, mío, tuyo, bienvenido, emocionado, asustado, enojado, orgulloso, aburrido, amigo, primo, maestro, doctor. This is standard AAC practice (one tile can't inflect), but confirm you're comfortable — a girl user hears the masculine form spoken about herself.
4. **Articles `core.a` → "un", `core.the` → "el".** Masculine-singular defaults, same as above — but the deeper question: do article tiles earn their grid slots in Spanish at all? Telegraphic Spanish drops them constantly ("quiero agua," not "quiero un agua"). Worth a conscious yes/no.
5. **Regional confirmations (all currently LatAm-leaning — correct for the audience, just confirming):** resbaladilla (slide; elsewhere "tobogán"), jalar (pull; Spain "tirar," which means "throw" in LatAm — so jalar must stay), carro (car; Spain "coche"), cuarto (bedroom; neutral would be "dormitorio"), chistoso (funny; Spain "gracioso").
6. **Duplicate-label strategy.** After the recommended fixes, remaining near-collisions: "no"/"no" (don't/no), "para"/"para" (stop/for, if you accept that fix). Decide whether identical spoken output on two tiles is acceptable when icons and positions differ.
7. **Missing concepts?** Not asked, but an SLP eye will notice: there is no "can" (puedo), no "don't want" distinct from "don't," and feelings has no "sad" (only sick/tired/hurt/scared/angry). Flagging in case the 50-word folder lists are meant to grow.
