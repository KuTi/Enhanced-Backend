###
  Pokemon Go (c) ManInTheMiddle Radar "mod"
  Michael Strassburger <codepoet@cpan.org>

  Enriches every PokeStop description with information about
  - directions to nearby wild pokemons
  - time left if a PokeStop has an active lure
###

changeCase = require 'change-case'
moment = require 'moment'
LatLon = require('geodesy').LatLonSpherical
state = require '../../state'
haversine = require 'haversine'

pokemons = []

module.exports = (server) ->
  # Parse the wild pokemons nearby
  server.addResponseHandler "GetMapObjects", (data) ->
    pokemons = []
    seen = {}
    addPokemon = (pokemon) ->
      return if seen[hash = pokemon.spawnpoint_id + ":" + pokemon.pokemon_data.pokemon_id]
      return if pokemon.time_till_hidden_ms < 0

      seen[hash] = true
      console.log "new wild pokemon", pokemon
      pokemons.push
        type: pokemon.pokemon_data.pokemon_id
        latitude: pokemon.latitude
        longitude: pokemon.longitude
        expirationMs: Date.now() + pokemon.time_till_hidden_ms
        data: pokemon.pokemon_data

    for cell in data.map_cells
      addPokemon pokemon for pokemon in cell.wild_pokemons

    false

  # Whenever a poke spot is opened, populate it with the radar info!
  server.addResponseHandler "FortDetails", (data) ->
    return unless state.config.pokestopRadar
    console.log "fetched fort request", data
    info = ""

    # Populate some neat info about the pokemon's whereabouts
    pokemonInfo = (pokemon) ->
      name = changeCase.titleCase pokemon.data.pokemon_id

      position = new LatLon pokemon.latitude, pokemon.longitude
      expires = moment(Number(pokemon.expirationMs)).fromNow()
      currentLocation = new LatLon state.location.latitude, state.location.longitude
      distance = Math.floor currentLocation.distanceTo position
      bearing = currentLocation.bearingTo position
      direction = switch true
        when bearing>330 then "↑"
        when bearing>285 then "↖"
        when bearing>240 then "←"
        when bearing>195 then "↙"
        when bearing>150 then "↓"
        when bearing>105 then "↘"
        when bearing>60 then "→"
        when bearing>15 then "↗"
        else "↑"

      "#{name} #{direction} #{distance}m expires #{expires}"

    # Create map marker for pokemon location
    pokemonMarker = (pokemon) ->
      label = pokemon.data.pokemon_id.charAt(0)
      icon = changeCase.paramCase pokemon.data.pokemon_id
      marker = "label:#{label}%7Cicon:http://raw.github.com/msikma/pokesprite/master/icons/pokemon/regular/#{icon}.png"

      "&markers=#{marker}%7C#{pokemon.latitude},#{pokemon.longitude}"

    for modifier in data.modifiers
      if modifier.item_id is 'ITEM_TROY_DISK'
        expires = moment(Number(modifier.expiration_timestamp_ms)).fromNow()
        info += "Lure by #{modifier.deployer_player_codename} expires #{expires}\n"

    if state.location?.latitude
      loc = "#{state.location.latitude},#{state.location.longitude}"
      img = "http://maps.googleapis.com/maps/api/staticmap?center=#{loc}&zoom=17&size=384x512&markers=color:blue%7Csize:tiny%7C#{loc}"

      if pokemons.length
        img += (pokemonMarker(pokemon) for pokemon in pokemons).join ""

      data.image_urls.unshift img

    info += if pokemons.length and state.location?.latitude
      (pokemonInfo(pokemon) for pokemon in pokemons).join "\n"
    else
      "No wild Pokémon near you..."

    data.description = info
    data
