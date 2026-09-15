// =====================================================
// EASTERN ETHIOPIA DIGITAL BROKER
// COMPLETE SCRIPT.JS
// SIGNUP + LOGIN + ROLE ROUTING
// =====================================================

console.log("EASTERN ETHIOPIA DIGITAL BROKER — SCRIPT.JS LOADED");


// =====================================================
// CHECK SUPABASE
// =====================================================

if (typeof supabaseClient === "undefined") {

    console.error(
        "ERROR: supabaseClient is not available."
    );

}


// =====================================================
// HELPER — NORMALIZE ROLE
// =====================================================

function normalizeRole(value) {

    const role = String(value ?? "")
        .trim()
        .toLowerCase();

    if (
        role === "jobseeker" ||
        role === "job-seeker" ||
        role === "job seeker"
    ) {
        return "job_seeker";
    }

    return role;
}


// =====================================================
// HELPER — SAFE REDIRECT
// =====================================================

function redirectByRole(role) {

    const normalizedRole = normalizeRole(role);

    console.log(
        "REDIRECTING ROLE:",
        normalizedRole
    );


    // -------------------------------------------------
    // SUPER ADMIN
    // -------------------------------------------------

    if (normalizedRole === "super_admin") {

        window.location.href =
            "admin-dashboard.html";

        return true;
    }


    // -------------------------------------------------
    // ADMIN
    // -------------------------------------------------

    if (normalizedRole === "admin") {

        window.location.href =
            "admin-dashboard.html";

        return true;
    }


    // -------------------------------------------------
    // CITY ADMIN
    // -------------------------------------------------

    if (normalizedRole === "city_admin") {

        window.location.href =
            "admin-dashboard.html";

        return true;
    }

    // -------------------------------------------------
    // EMPLOYER
    // -------------------------------------------------

    if (normalizedRole === "employer") {

        window.location.href =
            "employer-job-dashboard.html";

        return true;
    }


    // -------------------------------------------------
    // OWNER
    // -------------------------------------------------

    if (normalizedRole === "owner") {

        window.location.href =
            "owner-dashboard.html";

        return true;
    }


    // -------------------------------------------------
    // RENTER
    // -------------------------------------------------

    if (normalizedRole === "renter") {

        window.location.href =
            "renter-dashboard.html";

        return true;
    }


    // -------------------------------------------------
    // JOB SEEKER
    // -------------------------------------------------

    if (normalizedRole === "job_seeker") {

        window.location.href =
            "job-seeker-dashboard.html";

        return true;
    }


    return false;

}


// =====================================================
// STEP 6 — SIGNUP
// =====================================================

const signupForm =
    document.getElementById("signupForm");


if (signupForm) {

    console.log(
        "SIGNUP FORM FOUND"
    );


    signupForm.addEventListener(
        "submit",
        async function(event) {

            event.preventDefault();


            // =========================================
            // GET HTML ELEMENTS
            // =========================================

            const fullNameInput =
                document.getElementById("fullName");

            const phoneInput =
                document.getElementById("phone");

            const emailInput =
                document.getElementById("email");

            const passwordInput =
                document.getElementById("password");

            const roleInput =
                document.getElementById("role");

            const message =
                document.getElementById("message");

            const signupButton =
                document.getElementById("signupButton");


            if (
                !fullNameInput ||
                !phoneInput ||
                !emailInput ||
                !passwordInput ||
                !roleInput ||
                !message ||
                !signupButton
            ) {

                console.error(
                    "SIGNUP HTML ELEMENTS ARE MISSING"
                );

                return;
            }


            // =========================================
            // GET VALUES
            // =========================================

            const fullName =
                fullNameInput.value.trim();

            const phone =
                phoneInput.value.trim();

            const email =
                emailInput.value
                    .trim()
                    .toLowerCase();

            const password =
                passwordInput.value;

            const role =
                normalizeRole(
                    roleInput.value
                );


            // =========================================
            // VALIDATION
            // =========================================

            if (
                !fullName ||
                !phone ||
                !email ||
                !password ||
                !role
            ) {

                message.textContent =
                    "Please fill in all fields.";

                message.style.color =
                    "red";

                return;
            }


            if (password.length < 6) {

                message.textContent =
                    "Password must be at least 6 characters.";

                message.style.color =
                    "red";

                return;
            }


            // IMPORTANT:
            // Public signup must NEVER create
            // admin / super_admin / city_admin accounts.

            const allowedSignupRoles = [
                "owner",
                "renter",
                "job_seeker",
                "employer"
            ];


            if (
                !allowedSignupRoles.includes(role)
            ) {

                message.textContent =
                    "Invalid account role.";

                message.style.color =
                    "red";

                return;
            }


            signupButton.disabled =
                true;

            signupButton.textContent =
                "Creating account...";


            message.textContent =
                "Creating your account...";

            message.style.color =
                "black";


            try {

                // =====================================
                // CHECK SUPABASE
                // =====================================

                if (
                    typeof supabaseClient ===
                    "undefined"
                ) {

                    throw new Error(
                        "Supabase connection is not loaded."
                    );

                }


                // =====================================
                // CREATE AUTH ACCOUNT
                // =====================================

                console.log(
                    "STEP 1: CREATE AUTH USER"
                );


                const {
                    data: authData,
                    error: authError
                } =
                await supabaseClient.auth.signUp({

                    email:
                        email,

                    password:
                        password

                });


                if (authError) {

                    throw authError;

                }


                if (
                    !authData ||
                    !authData.user
                ) {

                    throw new Error(
                        "User account was not created."
                    );

                }


                const userId =
                    authData.user.id;


                console.log(
                    "AUTH USER CREATED:",
                    userId
                );


                // =====================================
                // CREATE PROFILE
                // =====================================

                console.log(
                    "STEP 2: CREATE PROFILE"
                );


                const {
                    data: profileData,
                    error: profileError
                } =
                await supabaseClient
                    .from("profiles")
                    .insert({

                        id:
                            userId,

                        full_name:
                            fullName,

                        phone:
                            phone,

                        role:
                            role

                    })
                    .select()
                    .single();


                if (profileError) {

                    console.error(
                        "PROFILE ERROR:",
                        profileError
                    );


                    throw new Error(
                        "Account was created, but the profile could not be saved: " +
                        profileError.message
                    );

                }


                console.log(
                    "PROFILE CREATED:",
                    profileData
                );


                // =====================================
                // SUCCESS
                // =====================================

                message.textContent =
                    "✅ Account created successfully!";

                message.style.color =
                    "green";


                signupButton.textContent =
                    "Account Created";


                setTimeout(
                    function() {

                        window.location.href =
                            "index.html";

                    },
                    1500
                );

            }


            catch(error) {

                console.error(
                    "SIGNUP ERROR:",
                    error
                );


                message.textContent =
                    error?.message ||
                    "Signup failed.";

                message.style.color =
                    "red";


                signupButton.disabled =
                    false;

                signupButton.textContent =
                    "Create Account";

            }

        }
    );

}


// =====================================================
// STEP 7 — LOGIN
// =====================================================

const loginForm =
    document.getElementById("loginForm");


if (loginForm) {

    console.log(
        "LOGIN FORM FOUND"
    );


    loginForm.addEventListener(
        "submit",
        async function(event) {

            event.preventDefault();


            console.log(
                "LOGIN SUBMIT INTERCEPTED"
            );


            // =========================================
            // GET HTML ELEMENTS
            // =========================================

            const emailInput =
                document.getElementById("loginEmail");

            const passwordInput =
                document.getElementById("loginPassword");

            const message =
                document.getElementById("loginMessage");

            const loginButton =
                document.getElementById("loginButton");


            if (
                !emailInput ||
                !passwordInput ||
                !message ||
                !loginButton
            ) {

                console.error(
                    "LOGIN HTML ELEMENTS ARE MISSING"
                );

                return;
            }


            // =========================================
            // GET VALUES
            // =========================================

            const email =
                emailInput.value
                    .trim()
                    .toLowerCase();

            const password =
                passwordInput.value;


            // =========================================
            // VALIDATION
            // =========================================

            if (
                !email ||
                !password
            ) {

                message.textContent =
                    "Please enter email and password.";

                message.style.color =
                    "red";

                return;
            }


            loginButton.disabled =
                true;

            loginButton.textContent =
                "Logging in...";


            message.textContent =
                "Connecting to account...";

            message.style.color =
                "black";


            try {

                // =====================================
                // CHECK SUPABASE
                // =====================================

                if (
                    typeof supabaseClient ===
                    "undefined"
                ) {

                    throw new Error(
                        "Supabase connection is not loaded."
                    );

                }


                // =====================================
                // SUPABASE LOGIN
                // =====================================

                console.log(
                    "STEP 1: SUPABASE LOGIN"
                );


                const {
                    data,
                    error
                } =
                await supabaseClient
                    .auth
                    .signInWithPassword({

                        email:
                            email,

                        password:
                            password

                    });


                if (error) {

                    throw error;

                }


                if (
                    !data ||
                    !data.user
                ) {

                    throw new Error(
                        "Login succeeded but no user was returned."
                    );

                }


                const userId =
                    data.user.id;


                console.log(
                    "STEP 2: AUTH LOGIN SUCCESS"
                );

                console.log(
                    "USER ID:",
                    userId
                );


                // =====================================
                // GET USER PROFILE
                // =====================================

                console.log(
                    "STEP 3: GET PROFILE"
                );


                const {
                    data: profile,
                    error: profileError
                } =
                await supabaseClient
                    .from("profiles")
                    .select(
                        "id,full_name,phone,role"
                    )
                    .eq(
                        "id",
                        userId
                    )
                    .maybeSingle();


                if (profileError) {

                    throw new Error(
                        "Login successful, but profile could not be loaded: " +
                        profileError.message
                    );

                }


                if (!profile) {

                    throw new Error(
                        "Your profile does not exist."
                    );

                }


                console.log(
                    "STEP 4: PROFILE FOUND"
                );

                console.log(
                    "PROFILE:",
                    profile
                );


                // =====================================
                // NORMALIZE ROLE
                // =====================================

                const role =
                    normalizeRole(
                        profile.role
                    );


                console.log(
                    "NORMALIZED ROLE:",
                    role
                );


                // =====================================
                // CHECK ROLE
                // =====================================

                const redirected =
                    redirectByRole(role);


                if (redirected) {

                    return;
                }


                // =====================================
                // INVALID ROLE
                // =====================================

                throw new Error(
                    "Invalid account role: " +
                    (
                        profile.role ||
                        "not assigned"
                    )
                );

            }


            catch(error) {

                console.error(
                    "================================"
                );

                console.error(
                    "LOGIN ERROR:",
                    error
                );

                console.error(
                    "================================"
                );


                message.textContent =
                    error?.message ||
                    "Login failed.";

                message.style.color =
                    "red";


                loginButton.disabled =
                    false;

                loginButton.textContent =
                    "Login";

            }

        }
    );

}


// =====================================================
// OPTIONAL — KEEP SESSION ACTIVE
// =====================================================

if (
    typeof supabaseClient !== "undefined"
) {

    supabaseClient.auth.onAuthStateChange(
        function(event, session) {

            console.log(
                "AUTH STATE:",
                event
            );


            if (event === "SIGNED_OUT") {

                console.log(
                    "USER SIGNED OUT"
                );

            }

        }
    );

}


// =====================================================
// END
// =====================================================

console.log(
    "EASTERN ETHIOPIA DIGITAL BROKER — SCRIPT.JS READY"
);