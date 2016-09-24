using ToxCore; // only in this file
using ToxEncrypt; // only in this file
using Ricin;

/**
* This class defines various methods, signals and properties related to toxcore handling.
* This class is intended to be used as an "intermediate" class between the .vapi and the Ricin code.
**/
public class Ricin.ToxSession : Object {
  /**
  * This property allow us to stop ToxCore internal loop simply. But we'll prefer using this.toxcore_stop().
  **/
  private bool tox_started { get; private set; default = false; }
  
  /**
  * This property is a switch to know whether or not Toxcore connected to the network.
  **/
  public bool tox_connected { get; private set; default = false; }

  /**
  * This property defines the loaded profile used in this instance.
  **/
  public Profile current_profile { get; private set; }

  /**
  * This defines the Tox instance from libtoxcore.vapi
  **/
  internal ToxCore.Tox tox_handle;

  /**
  * This aims to "cache" the options for the duration of the toxcore execution.
  **/
  public unowned ToxCore.Options? tox_options;

  /**
  * We keep a list of contacts thanks to the ContactsList class.
  **/
  private ContactsList contacts_list { private get; private set; }

  /**
  * Signal: Triggered once the Tox connection state changes.
  **/
  public signal void tox_connection (bool online);

  /**
  * Signal: Triggered once the Tox bootstraping state is finished.
  **/
  public signal void tox_bootstrap_finished ();

  /**
  * ToxSession constructor.
  * Here we init our ToxOptions, load the profile, init toxcore, etc.
  **/
  public ToxSession (Profile? profile, Options? options) {
    this.current_profile = profile;
    this.tox_options = options;

    // If options is null, let's use default values.
    if (this.tox_options == null) {
      // TODO:
      //Options opts = new Options.default ();
      //this.tox_options = opts;
    }

    ERR_NEW error;
    this.tox_handle = new ToxCore.Tox (this.tox_options, out error);

    /**
    * TODO: Write a class for the throwables errors.
    **/
    /*switch (error) {
      case ERR_NEW.NULL:
        throw new ErrNew.Null ("One of the arguments to the function was NULL when it was not expected.");
      case ERR_NEW.MALLOC:
        throw new ErrNew.Malloc ("The function was unable to allocate enough memory to store the internal structures for the Tox object.");
      case ERR_NEW.PORT_ALLOC:
        throw new ErrNew.PortAlloc ("The function was unable to bind to a port.");
      case ERR_NEW.PROXY_BAD_TYPE:
        throw new ErrNew.BadProxy ("proxy_type was invalid.");
      case ERR_NEW.PROXY_BAD_HOST:
        throw new ErrNew.BadProxy ("proxy_type was valid but the proxy_host passed had an invalid format or was NULL.");
      case ERR_NEW.PROXY_BAD_PORT:
        throw new ErrNew.BadProxy ("proxy_type was valid, but the proxy_port was invalid.");
      case ERR_NEW.PROXY_NOT_FOUND:
        throw new ErrNew.BadProxy ("The proxy address passed could not be resolved.");
      case ERR_NEW.LOAD_ENCRYPTED:
        throw new ErrNew.LoadFailed ("The byte array to be loaded contained an encrypted save.");
      case ERR_NEW.LOAD_BAD_FORMAT:
        throw new ErrNew.LoadFailed ("The data format was invalid. This can happen when loading data that was saved by an older version of Tox, or when the data has been corrupted. When loading from badly formatted data, some data may have been loaded, and the rest is discarded. Passing an invalid length parameter also causes this error.");
      default:
        throw new ErrNew.LoadFailed ("An unknown error happenend and ToxCore wasn't able to start.");
    }*/

    this.init_signals ();
    this.tox_bootstrap_nodes.begin ();
  }

  /**
  * This methods initialize all the tox callbacks and "connect" them to this class signals.
  **/
  private void init_signals () {
    // We get a reference of the handle, to avoid ddosing ourselves with a big contacts list.
    unowned ToxCore.Tox handle = this.tox_handle;
    
    handle.callback_self_connection_status ((self, status) => {
      switch (status) {
        case ConnectionStatus.NONE:
          debug ("Connection: None.");
          break;
        case ConnectionStatus.TCP:
          debug ("Connection: TCP.");
          break;
        case ConnectionStatus.UDP:
          debug ("Connection: UDP.");
          break;
      }

      this.tox_connected = (status != ConnectionStatus.NONE);
      this.tox_connection ((status != ConnectionStatus.NONE));
    });
  }

  /**
  * This methods handle bootstraping to the Tox network.
  * It takes care of reading and deserializing the dht-nodes.json file stored in resources.
  * It also takes care of bootstraping correctly by using TCP as a fallback, and IPv6 in priority.
  **/
  private async void tox_bootstrap_nodes () {
    debug ("B: Started Tox bootstraping process...");

    var json = new Json.Parser ();
    Bytes bytes;
    bool json_parsed = false;

    try {
      bytes = resources_lookup_data ("/im/ricin/client/jsons/dht-nodes.json", ResourceLookupFlags.NONE);
    } catch (Error e) {
      error (@"Cannot load dht-nodes.json, error: $(e.message)");
    }

    try {
      json_parsed = json.load_from_data ((string) bytes.get_data (), bytes.length);
    } catch (Error e) {
      error (@"Cannot parse dht-nodes.json, error: $(e.message)");
    }

    if (json_parsed) {
      debug ("B: dht-nodes.json was found, parsing it.");

      DhtNode[] nodes = {};
      var nodes_array = json.get_root ().get_object ().get_array_member ("servers");

      // Let's get our nodes from the JSON file as DhtNode objects.
      nodes_array.foreach_element ((array, index, node) => {
        nodes += ((DhtNode) Json.gobject_deserialize (typeof (DhtNode), node));
      });

      debug ("B: Parsed dht-nodes.json, bootstraping in progress...");

      while (!this.tox_connected) {
        // Bootstrap to 6 random nodes, faaast! :)
        for (int i = 0; i < 6; i++) {
          DhtNode rnd_node = nodes[Random.int_range (0, nodes.length)];

          bool success = false;
          bool try_ipv6 = this.tox_options.ipv6_enabled && rnd_node.ipv6 != null;

          // First we try UDP IPv6, if available for this node.
          if (!success && try_ipv6) {
            debug ("B: UDP bootstrap %s:%llu by %s", rnd_node.ipv6, rnd_node.port, rnd_node.owner);
            success = this.tox_handle.bootstrap (
              rnd_node.ipv6,
              (uint16) rnd_node.port,
              Utils.Helpers.hex2bin (rnd_node.pubkey),
              null
            );
          }

          // Then, if bootstrap didn't worked in UDP IPv6, we use UDP IPv4.
          if (!success) {
            debug ("B: UDP bootstrap %s:%llu by %s", rnd_node.ipv4, rnd_node.port, rnd_node.owner);
            success = this.tox_handle.bootstrap (
              rnd_node.ipv4,
              (uint16) rnd_node.port,
              Utils.Helpers.hex2bin (rnd_node.pubkey),
              null
            );
          }

          // If UDP didn't worked, let's do the same but with TCP IPv6.
          if (!success && try_ipv6) {
            debug ("B: TCP bootstrap %s:%llu by %s", rnd_node.ipv6, rnd_node.port, rnd_node.owner);
            success = this.tox_handle.add_tcp_relay (
              rnd_node.ipv6,
              (uint16) rnd_node.port,
              Utils.Helpers.hex2bin (rnd_node.pubkey),
              null
            );
          }

          // Then, if bootstrap didn't worked in TCP IPv6, we use TCP IPv4.
          if (!success) {
            debug ("B: TCP bootstrap %s:%llu by %s", rnd_node.ipv4, rnd_node.port, rnd_node.owner);
            success = this.tox_handle.add_tcp_relay (
              rnd_node.ipv4,
              (uint16) rnd_node.port,
              Utils.Helpers.hex2bin (rnd_node.pubkey),
              null
            );
          }
        }

        // We wait 5s without blocking the main loop.
        Timeout.add (5000, () => {
          this.tox_bootstrap_nodes.callback ();
          return false; // We could use Source.REMOVE instead but false is better for old GLib versions.
        });

        yield;
      }

      debug ("B: Boostraping to the Tox network finished successfully.");
      this.tox_bootstrap_finished ();
    }
  }

  /**
  * This methods allow to kill the ToxCore instance properly.
  **/
  private void tox_disconnect () {
    this.tox_started = true;

    this.tox_handle.kill ();
    this.tox_connection (false); // Tox connection stopped, inform the signal.
  }

  /**
  * Method to call in order to start toxcore execution loop.
  **/
  public void tox_run_loop () {
    this.tox_schedule_loop_iteration ();
  }

  /**
  * Iteration loop used to maintain the toxcore instance updated.
  **/
  private void tox_schedule_loop_iteration () {
    Timeout.add (this.tox_handle.iteration_interval (), () => {
      if (this.tox_started) { // Let's stop the iteration if this var is set to true.
        return true;
      }

      this.tox_handle.iterate ();
      this.tox_schedule_loop_iteration ();
      return false;
    });
  }
}
