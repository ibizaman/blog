---
title: Make Good Stubs with Stateful Property Testing
tags: go, testing
---

<!--toc:start-->
- [Context](#context)
- [Integration Tests](#integration-tests)
- [Where Mocks Fail](#where-mocks-fail)
- [Where Stubs Shine](#where-stubs-shine)
- [Conclusion](#conclusion)
<!--toc:end-->

## Context

In a previous post, I [wrote about how using stateful property testing][blog1] helped us find test cases that were hard to find by hand.
This helped us complete a project in a timely fashion.
But some other surprising benefits came from introducing stateful property testing.

[blog1]: https://blog.tiserbox.com/posts/2024-02-27-stateful-property-testing-in-go.html

To switch from a deprecated MongoDB driver to the official one, we created a regression test suite.
We first added stateful property tests, ensuring we covered as much behavior of the deprecated driver as we could.
We then could make the new driver behave the same way as the the old one by making it pass those same tests.
This gave us the confidence that both drivers behaved the same, even in edge cases, and that we could switch.

Well, having now these stateful property tests acting as a regression test suite, what else can we use them for?
Creating stubs.

## Integration Tests

Integration tests comprises a broad spectrum of test implementation.
On one side, you have the tests using real components, like a full MongoDB or Elasticsearch cluster.
Those suffer, from my experience, from flakiness, hard to reproduce differences on local dev and CI and are resource intensive and slow.

```go
import "testing"

func TestUser(t *testing.T) {
  db := CreateMongoDatabase(t)
}

func CreateMongoDatabse(t *testing.T) {
  // ?
}
```

Also, those are harder to setup.
The test there needs a MongoDB database, but who starts the MongoDB instance?
Is it done through the test suite, with for example [testcontainers][testcontainers]?
This has advantages, like full isolation between tests, but makes starting tests much slower since they each need to start a container.
Another possibility is to start them outside of the test suite, often in a not well loved shell script with its own flaws.

[testcontainers]: https://testcontainers.com/

On the other side, there are tests that use fake components - mocks - where the tester decides of the return value of those mocks during testing time.
These are fast but suffer from a lack of faithfulness as the bigger the mocked component, the harder it is to reproduce its real behavior.
This is even more true in a company with multiple engineering teams where one would mock a component made by another team.
Extensive documentation of behavior and edge cases is necessary for the mock to act like the real thing, but that's a hard to reach goal that's even harder to justify spending time on.

## Where Mocks Fail

I'd like to insist on the team aspect here and let's take an example for that.
I'll use the same example as in the previous blog post.
A Go service that encapsulates CRUD operations on a `User` struct representing a row in a MongoDB collection.
We'll focus on just one method, `GetByNameOrEmail`, which, although seemingly simple, already has quite a few edge cases.

```go
package userservice

type UserInterface interface {
  // GetByNameOrEmail retrieves a User from the database
  // by matching either on their name or email field.
  GetByNameOrEmail(nameOrEmail string) (*User, error)
}

// User struct represents a row or record in the
// database.
type User struct{
  ID          bson.ID
  Name        string
  Email       string
  Deleted     bool
  DeletedTime time.Time
}
```

Let's imagine this interface is given to us by another team.
We don't have access to the source code.
Well, we do, we're the same company, but maybe the code is too complicated for us and we don't understand it,
maybe it was created a long time ago and no one knows how it works anymore,
or maybe we actually can't read it because it's in a repo we don't have access to and getting access will require a few days to process.
So for this contrived exercise, we can't see the code.

Now we must program against this method and test our code.
We need to create a test for some code related to billing and we must retrieve a user at some point.
The point is, we're not on the team that maintains this user service.
Let's create a mock:

```go
type MockService() struct {
    GetByNameOrEmailNextCallReturn GetByNameOrEmailReturn
}

type GetByNameOrEmailReturn struct {
    User *User
    Err  error
}

func (ms MockService) GetByNameOrEmail(nameOrEmail string) (*User, error) {
    user, err := ms.GetByNameOrEmailNextCallReturn
    return user, err
}
```

Here you see how the mock works: at testing time, we instantiate the `MockService`
and then, before calling `GetByNameOrEmail`, we must ensure we set the `GetByNameOrEmailNextCallReturn` field to what we want that method to return.

But the follow-up question is what does this function returns?
In case of success, we can probably assume it returns a pointer to a filled out `User` struct and a `nil` error.
But we can't be sure of it without reading the source code.
Also, what if the `User` is not deleted, is the `DeletedTime` field set to the zero value of `time.Time` or to something else?

In case of error, we can probably assume the function returns a nil pointer for `User` and non-`nil` error.
Or maybe it's a pointer to a empty `User` struct?
Also, what will be the error?
Can we differentiate between a deleted and not deleted user?
Does the function return an error if the user is deleted?

So many questions that only the source code can tell us.
Actually, even by reading the other team's source code, we can't always tell what the error will look like.
If the code just returns the code from the MongoDB driver, we then need to go read the driver's documentation.
That's one good example of leaky abstraction.

Now, the worst part in my opinion is if you went the extra mile and actually managed to encapsulate the original function's behavior in a mock.
And then, the behavior of the real service changes.
You will never now and your test will still pass!
You will probably learn about it during the next deploy.

## Where Stubs Shine

Enter stubs.
They are still fast to create as they are just a Go struct.
The difference with mocks is that actually do try to encapsulate the behavior of the real object they're replacing.
They do this by managing an internal model that behaves the same way as the real deal.
A stub for the `User` service would look like so:

```go
type StubService() struct {
    Model map[bson.ID]User
}

func NewStubService() StubService {
  return StubService{
    Model: make(map[bson.ID]User),
  }
}

func (sus StubService) GetByNameOrEmail(nameOrEmail string) (*User, error) {
  // Assume we have a getByNameOrEmail function that searches in the map.
  user, ok := getByNameOrEmail(sus.model, nameOrEmail)
  if !ok {
    return nil, errors.New("No user found")
  } else if user.Deleted {
    return &user, errors.New("User is deleted")
  } else {
    return &user, nil
  }
}
```

Now let's be clear, the code inside that function does not follow best practices for error handling.
But maybe that's what we got because it matches the behavior of the real service.
And that service was made that way because of historical reasons.
Changing the service's behavior is tricky now and will definitely not be done by the team managing the billing system.

Anyway, the important part here is there is no mucking about figuring out what the method should return.
We instead insert the `User` we want in the model, then call the `GetByNameOrEmail` function.
The possibly weird behavior is encapsulated by the stub.

Of course, the issue now is how to create this stub?
This is where our earlier state property test acting as a regression test suite comes into play.
If the stub passes the same tests as the real service accessing MongoDB, then we can be quite sure it's acting like the real one!

Ideally, this stub is maintained by the team maintaining the real MongoDB service.
The additional work to do this is, by my experience, much smaller than the work needed to setup the stateful property tests anyway.
But even if that's not the case, as long as we have access to the tests, anyone can create a well behaved stub.

This is something we didn't have with mocks: we now have tests to test the stub.
And then we can use the stub in our tests.
It seems a bit roundabout but this chain of tests has a very nice property: it's a chain.
If one step in the chain changes, we are guaranteed to know if the rest of the chain breaks or not, before deploying to prod.
And if that's the case, we can assess if we want to pursue that change now or later and communicate about it before breaking prod.

## Conclusion

So are stubs always superior to mocks?
No, but in my experience, the usefulness of mocks is limited.
If you work alone on your own codebase, there are probably no big differences between a stub and a mock.
But if you're talking about multiple teams maintaining and evolving a codebase over multiple years, you want stubs first.
