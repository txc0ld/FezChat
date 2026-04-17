-- Seed the events table with the five events that previously shipped only in
-- Resources/events.json. Idempotent: re-running against a populated database
-- is a no-op. Apply once per environment after schema.sql.

INSERT INTO events (id, name, latitude, longitude, radius_meters, start_date, end_date, location, description, image_url, organizer_signing_key, attendee_count, category)
VALUES
    (
        'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'Splendour in the Grass',
        -28.7425, 153.5610, 2000.0,
        '2026-07-17T00:00:00Z', '2026-07-19T23:59:59Z',
        'North Byron Parklands, Byron Bay NSW',
        'Australia''s premier music festival featuring international and local artists across multiple stages in the Byron Bay hinterland.',
        '', '', 35000, 'festival'
    ),
    (
        'b2c3d4e5-f6a7-8901-bcde-f12345678901',
        'AFL Grand Final',
        -37.8200, 144.9834, 1500.0,
        '2026-09-26T00:00:00Z', '2026-09-26T23:59:59Z',
        'Melbourne Cricket Ground, Melbourne VIC',
        'The biggest day in Australian sport. 100,000 fans pack the MCG for the AFL Grand Final.',
        '', '', 100000, 'sport'
    ),
    (
        'c3d4e5f6-a7b8-9012-cdef-123456789012',
        'Ultra-Trail Australia',
        -33.7294, 150.3120, 5000.0,
        '2026-05-14T00:00:00Z', '2026-05-16T23:59:59Z',
        'Blue Mountains, Katoomba NSW',
        'World-class ultra marathon through the Blue Mountains. 100km, 50km, and 22km courses through ancient bushland.',
        '', '', 8500, 'marathon'
    ),
    (
        'd4e5f6a7-b8c9-0123-defa-234567890123',
        'Laneway Festival',
        -33.8688, 151.2093, 1000.0,
        '2026-02-07T00:00:00Z', '2026-02-07T23:59:59Z',
        'The Domain, Sydney NSW',
        'Inner-city music festival showcasing the best in indie, electronic, and alternative music.',
        '', '', 18000, 'concert'
    ),
    (
        'e5f6a7b8-c9d0-1234-efab-345678901234',
        'Vivid Sydney',
        -33.8568, 151.2153, 3000.0,
        '2026-05-22T00:00:00Z', '2026-06-13T23:59:59Z',
        'Sydney Harbour & CBD, Sydney NSW',
        'Festival of light, music, and ideas. Immersive light installations transform Sydney Harbour over three weeks.',
        '', '', 250000, 'other'
    )
ON CONFLICT (id) DO NOTHING;
