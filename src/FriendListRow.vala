[GtkTemplate (ui="/chat/tox/Ricin/friend-list-row.ui")]
class Ricin.FriendListRow : Gtk.ListBoxRow {
  [GtkChild] Gtk.Image avatar;
  [GtkChild] Gtk.Label username;
  [GtkChild] Gtk.Label status;

  public Tox.Friend fr;

  public FriendListRow (Tox.Friend fr) {
    this.fr = fr;
    fr.bind_property ("name", username, "label", BindingFlags.DEFAULT);
    fr.bind_property ("status-message", status, "label", BindingFlags.DEFAULT);
  }
}
