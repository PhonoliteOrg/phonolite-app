enum CarPlayListRequest {
  case artists(scope: CarPlayScope)
  case albums(scope: CarPlayScope, artistID: String)
  case playlists(scope: CarPlayScope)
}
