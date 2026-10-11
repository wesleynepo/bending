import Base

# Shared record types for the people API.

# A stored person. `id` is the UUID text assigned by Postgres, `birthdate` is YYYY-MM-DD.
type Person is Data:
  Person{id: String, name: String, birthdate: String}

# A validated create/update payload (no id: the database generates it).
type NewPerson is Data:
  NewPerson{name: String, birthdate: String}
