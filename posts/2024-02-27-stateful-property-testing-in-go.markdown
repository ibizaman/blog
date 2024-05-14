---
title: Use Case for Stateful Property Testing in Go
tags: go, testing
---

In this blog post, I'll explain what problem I tried to solve by introducing stateful property
testing at work, what is stateful property testing, how well that worked out and what other extra
benefits came along with stateful property testing.

# Our Initial Problem - A Driver Migration

We wanted to update our MongoDB database version but the driver we used did not support the new
version, was deprecated and did not get any updates. We needed to switch to the official MongoDB
driver first.

Switching drivers should not be too hard. Types and methods are pretty similar, the update is quite
mechanical. Of course, the devil is in the details and it appears there is an incompatible
representation of the ID type between both drivers. This caused issues during our first deploy where
a bug sneaked in spite of our existing tests.

We tried to add more tests but we couldn't come up with extensive enough tests even while knowing
about this incompatibility issue.

This ultimately let to multiple failed deploys. We could revert them easily and quickly but this
experience led to diminishing confidence in our capacity to deploy without issue.

# Business Logic Led To Combinatory Explosion When Testing

Before understanding how stateful property testing helped us to tame our codebase, we must first
review how our codebase is structured for accessing external dependencies.

Access to practically all external resources - like databases, internal and external services - is
done through a dedicated Go struct and methods.

For example, accessing a hypothetical "user" database table would be done through the following
code. I completely invented this example for the blog post but it's close to what we have.

```go
package userservice

// User struct represents a row or record in the
// database.
type User struct{
  ID          bson.ID
  name        string
  email       string
  deleted     bool
  deletedTime time.Time
}

// NewUser struct with only those fields relevant to
// creating or updating a new user.
type NewUser struct{
  name  string
  email string
}

// Service handles reading from and writing to
// the database.
type Service struct{
  dbHandle mongo.db
}

// New creates a Service.
func New(dbHandle) Service {
  return Service{dbHandle: dbHandle}
}

// Insert a user in the database.
func (us Service) Insert(u NewUser) (bson.ID, error)

// GetByNameOrEmail retrieves a User from the database
// by matching either on their name or email field.
func (us Service) GetByNameOrEmail(nameOrEmail string) (User, error)

// Update a user in the database. Fails if the ID does
// not correspond to an existing record.
func (us Service) Update(ID bson.ID, u NewUser) error

// SoftDelete a user by toggling its "deleted" flag to
// True.
func (us Service) SoftDelete(ID bson.ID) error

// Delete a user's record from the database. This will
// fail if the user was soft-deleted less than a week
// ago.
func (us Service) Delete(ID bson.ID) error
```

I left out the implementation as it does not matter for the purpose of the post. You can begin to
see why we had a hard time covering all the edge cases in our manual test suite. Some methods there
toggle flags that influence the expected result of others. For example in the above `Service`, the
`GetByNameOrEmail` method should only return matching users that had not been soft deleted
previously.

Now, we have about 25 services like the `UserService` that each handle accessing one table and each
of those have between 5 and 25 methods. This quickly leads to an unmanageable combinatory explosion
of test cases to cover.

We did have actual integration tests, using a real instance of a MongoDB to exercise those methods.
So we caught a lot of bugs that were introduced when migrating over to the new driver, but not all
of them.

# Property Testing

When testing a function, property testing is close to what we call in Go fuzzy testing. The idea is
to generate random inputs and assert that a certain property of the function we test is never
violated.

For example, let's test a Go function to deduplicate items from a slice. There are a few properties
we can test for:

1. The output's length has to be smaller than the input's length.
2. The output must only contain items that are in the input.
3. The input must only contain items that are in the output.
4. The output cannot contain twice the same item.

Some of those properties can overlap with others but it's good to be thorough.

Caveat #1 of property testing: coming up with properties to test is not easy.

The library we're using is called [rapid](https://github.com/flyingmutant/rapid). Here is how
testing the first properties would look like, assuming the deduplicating function is defined elsewere:

```go
import "testing"
import "flyingmutant/rapid"

func deduplicate[T comparable]([]T) []T

func TestingLength(t *testing.T) {
  rapid.Check(t, func (t *rapid.T) {
    input := rapid.SliceOf(rapid.Int()).Draw(t, "input slice")

    output := deduplicate(input)

    if len(output) > len(input) {
      t.Fatal("property violated: %d !<= %d", len(output), len(input))
    }
  })
}
```

_Note that the version used in the snippets here is for version `v0.7.2`. The interface changed a
bit since then but nothing that impacts what's discussed here._

The `rapid` library will run the `func (*rapid.T)` function a bunch of times with different inputs.
If an error is encountered, the library will reduce the input to the minimum input still showcasing
the error. In the example above, it will try to find the minimum input slice that still fails the
property. This is super useful for us humans to have as few noise as possible when trying to
understand where the error comes from.

Caveat #2 of property testing: how can you be sure that an input with two or more duplicate items
got generated? In a finite amount of time and tries, you can't with the test as written above.

We need to engineer the input to have a few duplicates. There are multiple ways to do that and I
usually choose the one that can be implemented with the less edge cases, in other words the one with
the less if clauses. Usually, you want to avoid needing to test your tests.

To generate a slice with randomly selected duplicates, I would do something like this:

```go
// This creates a slice generator. Use it like so:
//
//   inputSlice[int](100, 3).Draw(t, "slice with repeated items")
//
func inputSlice[T any](maxSize int, maxRepeat int) *rapid.Generator[[]T] {
  return rapid.Custom(func(t *rapid.T) []T {
    // Randomly draw size of input
    inputSize := rapid.IntRange(0, maxSize).Draw(t, "input slice length")
    input := make([]T, 0, inputSize)

    // For each item, generate 1 or more duplicate.
    for i := 0; i < inputSize; i++ {
      item := rapid.Make[T]().Draw(t, "item")
      repeat := rapid.IntRange(1, maxRepeat).Draw(t, "item repeat count")
      for r := 0; r < repeat; r++ {
        input = append(input, item)
      }
    }

    // Shuffle the items.
    rand.Shuffle(len(input), func(i, j int) {
      input[i], input[j] = input[j], input[i]
    })

    return input
  })
}
```

This will pick up to N randomly selected items, for each item repeat it up to M times and finally
return the randomly shuffled resulting slice.

As you can see, generating an input that covers all edge cases we want in a finite amount of tries
is hard but important. Alas, looking at that function, I would still probably need a test for it.

# Stateful Property Testing

Stateful property testing uses the same idea as property testing but applied to a go struct with
multiple methods where some of those methods can modify the struct's state.

As a first example, let's imagine the `User` struct - the one representing a row in our table - has
methods we want to test.

```go
// User struct we defined earlier. To simplify this
// section of the post, let's assume we only have a
// name and deleted field.
type User struct{
  name        string
  deleted     bool
}

func (u *User) SetName(name string) {
  u.name = true
}

func (u *User) GetName() string {
  return u.name
}

// SetDeleted modifies a flag on the User.
func (u *User) SetDeleted() {
  u.deleted = true
}

// IsDeleted returns the state of the flag.
func (u User) IsDeleted() bool {
  return u.deleted
}
```

Testing this using this `rapid` library looks like so. Since the `User` struct has a state - it
remembers it's name and if it's deleted - we want to check that this state behaves as we expect.

To do that, we create a model of this behavior - the `userStateMachine` struct in the following
example. There, we model a state machine where the delete state starts at `False` and the name
starts as the empty string. Calling `SetDeleted()` will transition the delete state to `True` and
`SetName()` will transition the name to the given value.

We must instruct `rapid` about this. We do it by creating this `userStateMachine` struct and adding
a few methods. We create one method for each relevant state we want to transition, here we create
`SetName()` and `Delete()` - the name itself do not matter - which will call the relevant method on
both the model and the real `User` struct we want to test. We then create a third method `Check()`
that is used to verify the real `User` struct's state matches the model.

As long as the `Check()` function succeeds, `rapid` will randomly pick between the `SetName()` and
`Delete()` method, execute it then call `Check()` again. It does that cycle about a 100 times by
default. If any method fails, it stops there and tries to replay the failure with smaller and
smaller inputs and prints the smallest input that still fails the test. For `rapid`, the input
includes the `name` given to `SetName()` but also the number of calls to `SetName()` and `Delete()`.
And that's really cool IMO.

```go
func TestUser(t *testing.T) {
  // Incantation needed by the rapid library.
  rapid.Check(t, func (t *rapid.T) {
    t.Repeat(rapid.StateMachineActions(&userStateMachine{}))
  })
}

// userStateMachine holds a User we want to test
// and a model of how the User should behave.
type userStateMachine struct {
  u User

  name      string
  isDeleted bool
}

// SetName modifies the state of the User and of
// the model.
func (usm *userStateMachine) SetName(t *rapid.T) {
  newName := rapid.String().Draw(t, "new name")

  // Call the method we want to test
  usm.u.SetName(newName)

  // Update our internal model
  usm.name = newName
}

// Delete modifies the state of the User and of
// the model.
func (usm *userStateMachine) Delete(t *rapid.T) {
  // Call the method we want to test
  usm.u.SetDeleted()

  // Update our internal model
  usm.isDeleted = true
}

// Check verifies that the User and the model agree on
// the state.
func (usm *userStateMachine) Check(t *rapid.T) {
  if usm.u.GetName() != usm.name {
    t.Fatalf("name: got (%s) != want (%s)",
             usm.u.GetName(), usm.name)
  }
  if usm.u.IsDeleted() != usm.isDeleted {
    t.Fatalf("deleted: got (%t) != want (%t)",
             usm.u.IsDeleted(), usm.isDeleted)
  }
}
```

# Stateful Property Testing to Tame The Combinatory Explosion

Now, let's apply what we just saw to the `Service` we defined earlier. Since the `Service` handles
access to a MongoDB collection, we will model the state with a map of IDs to `User` struct.

```go
// User struct we defined earlier.
type User struct{
  ID          bson.ID
  name        string
  email       string
  deleted     bool
  deletedTime time.Time
}

// NewUser struct with only those fields relevant to
// creating a new user.
type NewUser struct{
  name  string
  email string
}

func TestService(t *testing.T) {
  rapid.Check(t, func (t *rapid.T) {
    t.Repeat(rapid.StateMachineActions(&serviceStateMachine{
      // Give the initialized Service to the state machine.
      us: New(/* setup db access code */),

      // Start with an empty state.
      state: make(map[bson.ID]User),
    }))
  })
}

// serviceStateMachine holds a User we want to test
// and a model of how the User should behave.
type serviceStateMachine struct {
  // We test the Service.
  us Service

  // Against a model.
  state map[bson.ID]User
}

// Insert User, expects the insertion to always succeed
// because MongoDB chooses the ID and there are no unique
// contraint.
func (ssm serviceStateMachine) Insert(t *rapid.T) {
  // Generate a NewUser with random name and email.
  newUser := rapid.Make[NewUser]().Draw(t, "new user")

  // Insert the new User in the database.
  newID, err := ssm.us.Insert(newUser)
  if err != nil {
    t.Fatal(err)
  }

  // Add the new User to the state.
  ssm.state[newId] = User{
    ID: newId,
    name: newUser.name,
    email: newUser.email,
    deleted: false,
    deletedTime: time.Time{},
  }
}

// GetByNameOrEmailExisting tries to find a User we know
// exists either by its name or its email.
func (ssm serviceStateMachine) GetByNameOrEmailExisting(t *rapid.T) {
  // We purposely pick the user ID and not the User
  // struct here because then the only thing the rapid
  // library will log is the ID and not the full User
  // struct. It doesn't seem important at first, but
  // trust me when the User struct gets more fields
  // and you need to navigate through a lot of log
  // lines, reducing the log lines is a substantial
  // quality of life improvement.
  existingID := rapid.SampleFrom(lo.Keys(ssm.state)).Draw(t, "user ID")
  existingUser := ssm.state[existingID]
  nameOrEmail := rapid.OneOf(
    rapid.Just(existingUser.name),
    rapid.Just(existingUser.email),
  ).Draw(t, "name or email")

  // Get the User from the database.
  gotUser, err := ssm.us.GetByNameOrEmail(nameOrEmail)
  if err != nil {
    t.Fatal(err)
  }

  // Assert the user we got is the one we want.
  if diff := cmp.Diff(existingUser, gotUser); diff != "" {
    t.Fatalf("(-want, +got):\n%s", diff)
  }
}

// GetByNameOrEmailNotExisting tries to find a User using
// a random string and expects to fail.
func (ssm serviceStateMachine) GetByNameOrEmailNotExisting(t *rapid.T) {
  nameOrEmail := rapid.String().Draw(t, "random name or email")

  // Get the User from the database and assert we didn't
  // find it.
  _, err := ssm.us.GetByNameOrEmail(nameOrEmail)
  if err != NotFoundError {
    t.Fatal(err)
  }
}

// UpdateExisting tries to Update an existing User and
// expects to succeed.
func (ssm servicesStateMachine) UpdateExisting(t *rapid.T) {
  if len(ssm.state) == 0 {
    t.Skip("No existing user.")
  }
  existingID := rapid.SampleFrom(lo.Keys(ssm.state)).Draw(t, "user ID")
  existingUser := ssm.state[existingID]

  // Generate a NewUser with either an existing or randomly picked
  // name and email.
  updatedUser := NewUser{
    name = rapid.OneOf(rapid.String(), rapid.Just(existingUser.name)).Draw(t, "new user")
    email = rapid.OneOf(rapid.String(), rapid.Just(existingUser.email)).Draw(t, "new email")
  }

  // Update the User in the database.
  err := ssm.us.Update(existingID, updatedUser)
  if err != nil {
    t.Fatal(err)
  }

  // Update the state.
  u := ssm.state[existingID]
  u.name = updatedUser.name
  u.email = updatedUser.email
}

// UpdateNotExisting tries to Update an User that does not
// exist and expects to fail.
func (ssm servicesStateMachine) UpdateNotExisting(t *rapid.T) {
  randomID := rapid.Make[bson.ID]().Draw(t, "user ID")

  // Generate a NewUser with randomly picked name and email.
  updatedUser := NewUser{
    name = rapid.String().Draw(t, "new user")
    email = rapid.String().Draw(t, "new email")
  }

  // Update the User in the database.
  err := ssm.us.Update(randomID, updatedUser)
  if err == nil {
    t.Fatal("Expected error while updating the user")
  }
}

// SoftDeleteExisting tries to soft delete an existing User and
// expects to succeed.
func (ssm servicesStateMachine) SoftDeleteExisting(t *rapid.T) {
  if len(ssm.state) == 0 {
    t.Skip("No existing user.")
  }
  existingID := rapid.SampleFrom(lo.Keys(ssm.state)).Draw(t, "user ID")

  // Update the User in the database.
  err := ssm.us.SoftDelete(existingID)
  if err != nil {
    t.Fatal(err)
  }

  // Update the state. For the model, soft deleting is equivalent
  // to a plain delete.
  delete(ssm.state, existingID)
}

// SoftDeleteNotExisting tries to soft delete an User that does
// not exist and expects to fail.
func (ssm servicesStateMachine) SoftDeleteNotExisting(t *rapid.T) {
  randomID := rapid.Make[bson.ID]().Draw(t, "user ID")

  // Update the User in the database.
  err := ssm.us.SoftDelete(randomID)
  if err == nil {
    t.Fatal("Expected error while deleting the user")
  }
}

// DeleteExisting tries to delete an existing User and expects
// to succeed.
func (ssm servicesStateMachine) DeleteExisting(t *rapid.T) {
  if len(ssm.state) == 0 {
    t.Skip("No existing user.")
  }
  existingID := rapid.SampleFrom(lo.Keys(ssm.state)).Draw(t, "user ID")

  // Update the User in the database.
  err := ssm.us.Delete(existingID)
  if err != nil {
    t.Fatal(err)
  }

  // Update the state.
  delete(ssm.state, existingID)
}

// DeleteNotExisting tries to soft delete an User that does
// not exist and expects to fail.
func (ssm servicesStateMachine) DeleteNotExisting(t *rapid.T) {
  randomID := rapid.Make[bson.ID]().Draw(t, "user ID")

  // Update the User in the database.
  err := ssm.us.Delete(randomID)
  if err == nil {
    t.Fatal("Expected error while deleting the user")
  }
}
```

As you can see from the snippets above, we still need to define, for each method we test, every
possible edge case. Usually for services that access databases, a common edge case is if a user
exists or not. Depending on that, the test expects the function call to succeed or not.

I like the snippet above because it shows that although we call different methods on the `Service`
for deletion and soft deletion, we expect the behavior to be the same in both cases - the affected
`User` should not be found anymore. The model reflects that as in both cases we `delete` the `User`.

Then, stateful property testing kicks in by randomly trying combinations of the edge cases we
defined. The good news is we can focus on each method in isolation, just thinking about how each of
the `User` field interact with the expected result of the methods on the `Service` struct. The
`rapid` library takes care of taming the combinatory explosion.

There's a few more things I'd like to call out from the snippet above.

- This is a lot of code. More than me and my team were initially comfortable to write for tests. In
  the end, it was worth it.
- In the long run, logging too much becomes annoying as it is just noise. That's why when randomly
  choosing a User that exists, it's better to pick the ID than the User struct directly, otherwise
  you print fields that you don't care about.
- We usually split the various edge cases in multiple methods. In the snippet, we have the
  `Existing` and `NotExisting` suffixed methods. You could do the same in one function but then you
  need a way to know if you picked an existing user or not and you begin to fiddle with if clauses
  everywhere. In the end, splitting into multiple methods makes the test code easier to understand.
- Since we only have a finite time to run the test, the more edge cases you have, the less chance
  you'll have to actually exercise all the edge case combinations in one test run. There are two
  ways to go about that: input generation engineering and classification. We covered the former
  above.

Classification means we add a label to each edge case. Each time an edge case gets reached, we
increment the related label's counter by 1. At the end of the test, we generate a report that shows
the distribution of edge case. We can then analyze this distribution to ensure all the edge cases
got reached a sufficient amount of times. If not, we need to either run the tests longer or to
either change how we generate the inputs. Classification is in general useful when we have a lot of
edge cases.

# Great Success

Setting up the stateful property tests to cover most if not all of the edge cases we could think of
was no easy task, but it was really rewarding as it discovered all remaining incompatibility issues.
Although the team was not enthusiastic in introducing that kind of testing in the first place - and
rightfully, it's quite a lot of code - the result put everyone on board and boosted the confidence
in deploying our changes.

In a following post, I will talk about an additional benefit of the stateful property tests as we
wrote them: they allowed to switch from mocks to stubs. We will see how they helped and just why
switching to stub is a good idea in the first place.
