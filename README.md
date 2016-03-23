# Simple REST client

WARNING: Currently in prototype stage!

Gem to aid construction of [REST](https://en.wikipedia.org/wiki/Representational_state_transfer) API clients, focused on the following principles:

* Use Ruby's [idioms](https://en.wikipedia.org/wiki/Programming_idiom) whenever possible.
* Use known [design patterns](https://en.wikipedia.org/wiki/Software_design_pattern).
* Prefer [convention over configuration](https://en.wikipedia.org/wiki/Convention_over_configuration).
  * Usual cases should work of the shelf.
* Single thread over multi-thread concurrent code.
  * Lower code complexity.
  * Use [thread local](https://en.wikipedia.org/wiki/Thread-local_storage) objects for multi-thrad environments.
* Use persistent connection, but no connection pool.
  * Lower code complexity.
  * More resilience.
  * Query throughput.
* Provide "low level" HTTP methods access as well "high level" abstractions (eg: internal JSON parsing).
* Aid pagination though an Enumerable object.
* Avoid [dependency hell](https://en.wikipedia.org/wiki/Dependency_hell) pitfalls.
  * No fancy dependencies, use Ruby's standard libraries.
  * Respect [Semantic Versioning](http://semver.org/), with a twist: when there is an incompatible API change, create a Gem with a new name, to allow one to use in the same project, both previous and a newer version.
* Do not use class level client configuration, instead, use instance level configuration, allowing connection to the same API but with different credentials for example.
* Meaningful exceptions with useful informative messages to ease debugging.
