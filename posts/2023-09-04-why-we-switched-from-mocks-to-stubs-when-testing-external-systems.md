---
title: Why we switched from mockx to stubs when testing external systems
tags: go
wip: true
---


In our codebase, access to practically all external resources (databases, other internal or external services) is done through a dedicated Go struct with dedicated methods.

For example, to access the MongoDB User collection, you must initialize a User struct with a connection pool previously initiated. Then, you pass around this User instance in your codebase. The trick is that every function accepting this User struct actually expects a Go interface with the functions it needs. This way, in prod we give it the real deal but in tests we give it something else.

As a small aside, we used to define one User interface next to the User struct, in a central place, and which had all the available methods. And every function in the codebase was using this giant interface. One thing I’m actively slowly changing is to avoid using those giant interfaces and instead relying on small interfaces defined where they will be used.

So we have some integration test exercising the methods of this User struct. Those are for example inserting a user and getting it back and then comparing what we got with what we put in. Some methods are not even tested.

Then, you have the test of the function using that User interface. We’re giving it a mock of the User struct. By mock, I mean a “UserMock” struct engineered to respond with a pre-determined answer when called on certain methods. For example, we can say to the mock, if your Insert() error method is called, respond with a nil error, or with an actual error we give you.

The whole issue IMO with mocks in this context, is when you’re testing these functions using the User interface, you must also understand how the real User struct will behave. But that’s not the right time to care about that. And most often, those testing the function do not know how the real User struct will behave, especially for edge cases.

Another big issue with mocks is what happens when one of the User struct method changes behavior? How can the one changing the behavior know all the tests to update across the codebase? Nothing can help them here.

Also, if a test using this mock breaks, where does the issue lie? Could it be how we told the mock to behave that’s wrong? Even if the test passed, the mock behavior could be wrong. So many subtle things could be wrong.

Enters stubs.

Here the idea is to have yet another struct implementing this User interface. But the struct is engineered to behave as close to possible as the real User struct which accesses the database but it doesn’t access the real DB. Instead, it works on an in-memory structure.

This stub would be provided by those implementing the real User struct. This moves the responsibility of understanding the behavior of the real struct to those best suited to understand and care about it.

Using this stub in tests would not be more difficult than using the real one. You could even have your binary use that stub when it’s running, on your local machine for example.

Anyway, all the issues with mocks go away with stubs. You’re sure, when using it, that edge cases are taken into consideration correctly. If your test fails, the issue is probably not in the stub. If someone wants to update the behavior of a function, every use of the stub gets updated and you can see tests failing if they don’t handle the new behavior.

That’s what I’m pushing for in our codebase.

But that leaves one last thing to do. How can we be confident that the stub behavior matches the real one?

The solution came from another project we undertook. Switching from a deprecated Go MongoDB driver to the official one.

The first few Go struct that accesses individual collection we ported over were done on good faith. And we had 5 outages because of that. The issues were all related to not enough tests. But I don’t blame anyone on not having the will to add them. Testing for all the edge cases of 15 methods times 10 is a daunting task. The combinatory explosion is really an explosion here. Btw, the main reason we had issues was incompatibilities with the ID types between the old and new driver. They passed our tests but still caused outages.

The solution came from something I came across, property testing. And more precisely, stateful property testing. We use this library, see the example here https://pkg.go.dev/pgregory.net/rapid#T.Repeat

Let’s take the Insert user and Find user methods as example. Our method for testing them is to have a test suite to:
- generate a random not existing user, call the insert method and assert it succeeds.
- generate a user with an ID or email or whatever your unique index is already in the database and assert the Insert method fails because of duplicate error.
- Find a user with an ID or email we know exist and assert we get the user we expect
- Find a user with an ID or email we know does not exist and assert we get a not found error
And we have test cases like that for all the edge cases we thought of.

Each test case there updates an in-memory model of how we thing the DB should behave. With the 4 example above, the 1st one would add the generated user in the model while the second would not. Also, we use the model to know what ID already exist to craft edge cases.

We then let the property testing library do its thing and try out all the above test cases in random order with random inputs and after each test it asserts the thing we test matches the model we have. If not, it stops, tries to reduce the input and spits the error.

For the driver migration project, we created a test suite for each migration, fixed the encountered errors and deployed. Personally it’s a huge success because I introduced this against the (healthy) skepticism of my teammates and it turned out to be a huge success. We didn’t have any outages in the migrations using this property testing method. And that boosted my teammates confidence in the deploys.

For the stubs, I had an epiphany when I realized we could just use the test suite from the real User struct with the methods accessing the DB on the stub one. If both pass the same test suite, we’re pretty confident both behave the same way, at least for what we tested them for.

So that’s how we’re somewhat guaranteeing that the stub and real thing matches in behavior.

Btw, I was the one introducing mocks usage in our codebase and now I’m coming back from that and introducing something else. We’ll see how that goes in a few years.

Good question. I’m not sure, I didn’t ponder too much on other usages.

I think I do not like the philosophy behind mocks where you are in charge of the internals of a system that’s not tied to the current test. Although the only way IMO to have a good stub is to invest a lot of time and to know what you’re doing.

So, when you can’t use stubs, I really like using mocks like with the gomock library.

I wonder how much of using stubs instead of mocks come from needing to inject errors. In the stub we use, we added additional methods like SetErrorOnNextFind to inject errors. It’s not perfect and we’ll see how it scales.

That being said, I think you can do the same thing with stubs and mocks. Just that it looks from my experience that stubs are more scalable and maintainable since they’re reusable. You can re-use other ppl’s experience more easily
