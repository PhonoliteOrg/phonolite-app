enum CarPlayCommand {
  case playLiked(scope: CarPlayScope)
  case startLibraryShuffle(scope: CarPlayScope)
  case playAlbum(scope: CarPlayScope, albumID: String)
  case playPlaylist(scope: CarPlayScope, playlistID: String)
}
